import AppKit
import CoreGraphics
import SceneKit
import SwiftUI

/// Interactive preview of the same solid used for STL export.
struct Cartridge3D: NSViewRepresentable {
    let model: ConsoleModel
    let geometry: Geometry
    let artwork: ArtworkOptions?

    func makeCoordinator() -> CartridgeScene { CartridgeScene(model: model) }

    func makeNSView(context: Context) -> CartridgeView3D {
        let view = CartridgeView3D(frame: .zero)
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling4X
        context.coordinator.configure(in: view)
        return view
    }

    func updateNSView(_ view: CartridgeView3D, context: Context) {
        context.coordinator.update(geometry: geometry, artwork: artwork)
    }
}

final class CartridgeView3D: SCNView {
    override var isOpaque: Bool { false }
    override var acceptsFirstResponder: Bool { allowsCameraControl }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        guard allowsCameraControl, let key = event.charactersIgnoringModifiers else {
            return super.keyDown(with: event)
        }
        switch key {
        case "\u{F702}": defaultCameraController.rotateBy(x: -8, y: 0) // Left arrow.
        case "\u{F703}": defaultCameraController.rotateBy(x: 8, y: 0)  // Right arrow.
        case "\u{F700}": defaultCameraController.rotateBy(x: 0, y: -8) // Up arrow.
        case "\u{F701}": defaultCameraController.rotateBy(x: 0, y: 8)  // Down arrow.
        case "+", "=", "-":
            if let camera = pointOfView?.camera {
                let factor: CGFloat = key == "-" ? 1.1 : 0.9
                camera.fieldOfView = min(70, max(12, camera.fieldOfView * factor))
            }
        default:
            super.keyDown(with: event)
        }
    }
}

@MainActor
final class CartridgeScene {
    let scene = SCNScene()
    let camera = SCNNode()
    private let body = SCNNode()
    private let label = SCNNode()
    private let plane = SCNPlane()
    private let labelMaterial = SCNMaterial()
    private let nominalWidth: CGFloat
    private let meshIsAvailable: Bool
    private var currentSize: CGSize?
    private var currentTexture: TextureKey?

    init(model: ConsoleModel) {
        scene.background.contents = NSColor.clear
        camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 36
        camera.camera?.zNear = 1
        camera.camera?.zFar = 2_000
        scene.rootNode.addChildNode(camera)

        nominalWidth = model.profile.geometry.body.width
        guard let mesh = STLMesh(file: model.mesh) else {
            meshIsAvailable = false
            return
        }

        meshIsAvailable = true
        let plastic = SCNMaterial()
        plastic.lightingModel = .blinn
        plastic.diffuse.contents = NSColor(Color(cartrestHex: model.profile.palette.plastic))
        plastic.specular.contents = NSColor(white: 0.19, alpha: 1)
        plastic.shininess = 0.24
        mesh.geometry.firstMaterial = plastic
        body.geometry = mesh.geometry
        scene.rootNode.addChildNode(body)

        labelMaterial.lightingModel = .constant
        labelMaterial.blendMode = .alpha
        labelMaterial.writesToDepthBuffer = false
        plane.firstMaterial = labelMaterial
        label.geometry = plane
        label.isHidden = true
        scene.rootNode.addChildNode(label)

        addLight(.ambient, intensity: 500)
        addLight(.directional, intensity: 900, position: SCNVector3(-80, 140, 200))
        addLight(.directional, intensity: 380, position: SCNVector3(140, -100, -170))
    }

    func configure(in view: CartridgeView3D) {
        guard meshIsAvailable else {
            let notice = NSTextField(wrappingLabelWithString: "The cartridge model is unavailable for the 3D preview.")
            notice.textColor = .white
            notice.alignment = .center
            notice.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(notice)
            NSLayoutConstraint.activate([
                notice.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                notice.centerYAnchor.constraint(equalTo: view.centerYAnchor),
                notice.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 16),
                notice.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -16),
            ])
            return
        }

        view.scene = scene
        view.pointOfView = camera
        view.allowsCameraControl = true
        view.cameraControlConfiguration.allowsTranslation = false
        view.cameraControlConfiguration.autoSwitchToFreeCamera = false
        view.defaultCameraController.pointOfView = camera
        view.defaultCameraController.target = SCNVector3Zero
        view.defaultCameraController.interactionMode = .orbitArcball
        view.setAccessibilityElement(true)
        view.setAccessibilityLabel("3D coaster preview")
        view.setAccessibilityHelp("Drag or use the arrow keys to rotate. Scroll or use the plus and minus keys to zoom.")
    }

    func update(geometry: Geometry, artwork: ArtworkOptions?) {
        guard meshIsAvailable else { return }
        let size = CGSize(width: geometry.body.width, height: geometry.body.height)
        let longSide = max(size.width, size.height)
        if currentSize != size {
            // The preview applies the same proportional size as the exported STL.
            let factor = size.width / nominalWidth
            body.scale = SCNVector3(factor, factor, factor)
            body.position = SCNVector3(-size.width / 2, -size.height / 2, -geometry.body.thickness / 2)

            if let previousSize = currentSize {
                // Resizing preserves the viewing angle and relative zoom.
                let factor = longSide / max(previousSize.width, previousSize.height)
                let position = camera.position
                camera.position = SCNVector3(position.x * factor, position.y * factor, position.z * factor)
            } else {
                camera.position = SCNVector3(longSide * 0.49, -longSide * 0.57, longSide * 2.02)
                camera.look(at: SCNVector3Zero)
            }
            currentSize = size
        }

        let trim = geometry.label
        plane.width = trim.width
        plane.height = trim.height
        label.position = SCNVector3(
            trim.x + trim.width / 2 - size.width / 2,
            size.height / 2 - trim.y - trim.height / 2,
            // Lift the label slightly above the recess floor to prevent z-fighting.
            geometry.body.thickness / 2 - geometry.recess.depth + 0.025
        )

        guard let artwork else {
            label.isHidden = true
            labelMaterial.diffuse.contents = nil
            currentTexture = nil
            return
        }
        let key = TextureKey(artwork)
        guard key != currentTexture else { return }
        let image = labelTexture(artwork)
        labelMaterial.diffuse.contents = image.map { NSImage(cgImage: $0, size: .zero) }
        label.isHidden = image == nil
        currentTexture = key
    }

    private func addLight(_ type: SCNLight.LightType, intensity: CGFloat, position: SCNVector3 = SCNVector3Zero) {
        let node = SCNNode()
        let light = SCNLight()
        light.type = type
        light.intensity = intensity
        node.light = light
        scene.rootNode.addChildNode(node)
        if type == .directional {
            node.position = position
            node.look(at: SCNVector3Zero)
        }
    }
}

private struct TextureKey: Equatable {
    let image: ObjectIdentifier
    let crop: [CGFloat]

    init(_ artwork: ArtworkOptions) {
        image = ObjectIdentifier(artwork.image)
        crop = [
            artwork.widthMM, artwork.heightMM, artwork.radiusMM, artwork.chamferMM,
            artwork.bleedMM, artwork.zoom, artwork.x, artwork.y,
        ]
    }
}

private func labelTexture(_ artwork: ArtworkOptions) -> CGImage? {
    let width = artwork.widthMM
    let height = artwork.heightMM
    let longSide = max(width, height)
    guard width.isFinite, height.isFinite, width > 0, height > 0 else { return nil }

    // Use the export crop with a separate texture resolution for the preview.
    let widthPX = max(1, Int((width / longSide * 1_024).rounded()))
    let heightPX = max(1, Int((height / longSide * 1_024).rounded()))
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(
              data: nil, width: widthPX, height: heightPX, bitsPerComponent: 8, bytesPerRow: 0,
              space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          )
    else { return nil }

    let scaleX = CGFloat(widthPX) / width
    let scaleY = CGFloat(heightPX) / height
    // The crop starts at the top left and the Quartz bitmap starts at the bottom left.
    var transform = CGAffineTransform(a: scaleX, b: 0, c: 0, d: -scaleY, tx: 0, ty: CGFloat(heightPX))
    let trim = outline(
        in: CGRect(x: 0, y: 0, width: width, height: height), radius: artwork.radiusMM, chamfer: artwork.chamferMM
    )
    guard let path = trim.copy(using: &transform) else { return nil }
    context.addPath(path)
    context.clip()
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: widthPX, height: heightPX))

    let metrics = ArtworkExporter.measure(artwork)
    let bleed = (metrics.artworkWidthMM - width) / 2
    let image = ArtworkExporter.imageRect(artwork)
    context.interpolationQuality = .high
    context.draw(artwork.image, in: CGRect(
        x: (image.minX - bleed) * scaleX, y: (height - image.maxY + bleed) * scaleY,
        width: image.width * scaleX, height: image.height * scaleY
    ))
    return context.makeImage()
}

@MainActor
private struct STLMesh {
    let geometry: SCNGeometry

    init?(file: CartridgeSTL) {
        // Each binary STL facet stores one normal and three vertices. Keep the vertices separate
        // so the face, chamfer and recess walls retain their sharp edges.
        var vertices = [SCNVector3]()
        var normals = [SCNVector3]()
        vertices.reserveCapacity(file.facetCount * 3)
        normals.reserveCapacity(file.facetCount * 3)

        func sceneVector(_ vector: SIMD3<Float>) -> SCNVector3 {
            SCNVector3(CGFloat(vector.x), CGFloat(vector.y), CGFloat(vector.z))
        }
        file.forEachFacet { normal, a, b, c in
            vertices.append(contentsOf: [sceneVector(a), sceneVector(b), sceneVector(c)])
            let direction = sceneVector(normal)
            normals.append(contentsOf: [direction, direction, direction])
        }
        let vertexSource = SCNGeometrySource(vertices: vertices)
        let normalSource = SCNGeometrySource(normals: normals)
        let triangles = SCNGeometryElement(indices: vertices.indices.map(UInt32.init), primitiveType: .triangles)
        geometry = SCNGeometry(sources: [vertexSource, normalSource], elements: [triangles])
        let (minimum, maximum) = geometry.boundingBox
        guard maximum.x > minimum.x, maximum.y > minimum.y, maximum.z > minimum.z else { return nil }
    }
}
