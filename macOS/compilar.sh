#!/bin/bash
set -euo pipefail

pasta_mac="$(cd -- "$(dirname -- "$0")" && pwd -P)"
projeto="$(dirname -- "$pasta_mac")"
destino="$projeto/Cartrest.app"
arquiteturas=("$(/usr/bin/uname -m)")
versao=""

uso() {
  printf 'Uso: %s [--release] [--versao X.Y.Z] [--saida CAMINHO/Cartrest.app]\n' "$0"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --release)
      arquiteturas=(arm64 x86_64)
      shift
      ;;
    --versao|--saida)
      if [[ $# -lt 2 || -z "$2" || "$2" == --* ]]; then
        uso >&2
        exit 2
      fi
      if [[ "$1" == --versao ]]; then
        versao="$2"
      else
        destino="$2"
      fi
      shift 2
      ;;
    -h|--help)
      uso
      exit 0
      ;;
    *)
      uso >&2
      exit 2
      ;;
  esac
done

if [[ -n "$versao" && ! "$versao" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  printf 'Use uma versão no formato X.Y.Z.\n' >&2
  exit 2
fi
if [[ "$(basename -- "$destino")" != Cartrest.app || -L "$destino" ]]; then
  printf 'A saída deve ser um caminho para Cartrest.app.\n' >&2
  exit 2
fi
if [[ ! -f "$pasta_mac/Cartrest/CartrestApp.swift" ]]; then
  printf 'Ponto de entrada ausente em %s\n' "$pasta_mac/Cartrest/CartrestApp.swift" >&2
  exit 1
fi

/bin/mkdir -p "$(dirname -- "$destino")"
pasta_destino="$(cd -- "$(dirname -- "$destino")" && pwd -P)"
destino="$pasta_destino/Cartrest.app"

# O bundle temporário fica no mesmo volume da saída para permitir um rename atômico.
temporario="$(/usr/bin/mktemp -d "$pasta_destino/.cartrest-compilacao.XXXXXX")"
trap '/bin/rm -rf -- "$temporario"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

app="$temporario/Cartrest.app"
conteudo="$app/Contents"
recursos="$conteudo/Resources"
plist="$conteudo/Info.plist"
/bin/mkdir -p "$conteudo/MacOS" "$recursos"
/usr/bin/install -m 644 "$pasta_mac/Info.plist" "$plist"
/usr/bin/install -m 644 "$pasta_mac/Cartrest.icns" "$recursos/Cartrest.icns"
/usr/bin/install -m 644 "$pasta_mac/Recursos/mare-alta.png" "$recursos/mare-alta.png"
/usr/bin/install -m 644 "$projeto/modelo/dimensoes.json" "$recursos/dimensoes.json"
/usr/bin/install -m 644 "$projeto/modelo/cartrest-ds-100mm.stl" "$recursos/cartrest-ds-100mm.stl"
if [[ -n "$versao" ]]; then
  /usr/bin/plutil -replace CFBundleShortVersionString -string "$versao" "$plist"
  /usr/bin/plutil -replace CFBundleVersion -string "$versao" "$plist"
fi
/usr/bin/plutil -lint "$plist" >/dev/null

if [[ -e "$destino" ]]; then
  identificador="$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$plist")"
  identificador_anterior="$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$destino/Contents/Info.plist" 2>/dev/null || true)"
  if [[ "$identificador_anterior" != "$identificador" ]]; then
    printf 'Já existe outro item em %s. Escolha outra pasta de saída.\n' "$destino" >&2
    exit 1
  fi
fi

versao_minima="$(/usr/bin/plutil -extract LSMinimumSystemVersion raw -o - "$plist")"
sdk="$(/usr/bin/xcrun --sdk macosx --show-sdk-path)"
executaveis=()
for arquitetura in "${arquiteturas[@]}"; do
  executavel="$temporario/Cartrest-$arquitetura"
  /usr/bin/xcrun --sdk macosx swiftc \
    -target "${arquitetura}-apple-macos${versao_minima}" -sdk "$sdk" \
    -parse-as-library -O -whole-module-optimization "$pasta_mac"/Cartrest/*.swift \
    -o "$executavel"
  executaveis+=("$executavel")
done

# Cada arquitetura precisa ser compilada com o target certo. O lipo só junta as fatias.
binario="$conteudo/MacOS/Cartrest"
if [[ ${#executaveis[@]} -eq 1 ]]; then
  /bin/mv "${executaveis[0]}" "$binario"
else
  /usr/bin/xcrun lipo -create "${executaveis[@]}" -output "$binario"
fi
for arquitetura in "${arquiteturas[@]}"; do
  /usr/bin/xcrun lipo "$binario" -verify_arch "$arquitetura"
done

# A assinatura cobre o bundle final. A opção de Developer ID inclui o runtime reforçado.
identidade="${CARTREST_CODESIGN_IDENTITY:--}"
if [[ "$identidade" == - ]]; then
  /usr/bin/codesign --force --sign - --timestamp=none "$app"
else
  /usr/bin/codesign --force --sign "$identidade" --options runtime --timestamp "$app"
fi
/usr/bin/codesign --verify --strict --all-architectures "$app"

# RENAME_SWAP mantém a versão anterior disponível até a nova estar compilada e assinada.
/usr/bin/xcrun swift - "$app" "$destino" <<'SWIFT'
import Darwin

let origem = CommandLine.arguments[1]
let destino = CommandLine.arguments[2]
if renamex_np(origem, destino, UInt32(RENAME_EXCL)) != 0 {
    guard errno == EEXIST, renamex_np(origem, destino, UInt32(RENAME_SWAP)) == 0 else {
        perror("Falha ao publicar Cartrest.app")
        exit(EXIT_FAILURE)
    }
}
SWIFT

printf 'Aplicativo pronto em %s\n' "$destino"
