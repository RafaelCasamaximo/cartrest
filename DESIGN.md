---
name: Cartrest
description: "Editor nativo de adesivos sobre uma prancheta em milímetros."
colors:
  janela-clara: "#F4F5F0"
  janela-escura: "#18211F"
  inspetor-claro: "#EAF0E9"
  inspetor-escuro: "#202B27"
  rodape-claro: "#E3EBE3"
  rodape-escuro: "#26332E"
  selecao-clara: "#D4E8D9"
  selecao-escura: "#31493E"
  contorno-selecao-claro: "#82A995"
  contorno-selecao-escuro: "#5B856E"
  divisor-claro: "#C4D3C9"
  divisor-escuro: "#3B4D45"
  acento-claro: "#24664B"
  acento-escuro: "#29734F"
  destaque-claro: "#2A593F"
  destaque-escuro: "#BBDBBF"
  tapete-luz: "rgb(10.5% 24% 19%)"
  tapete-centro: "rgb(7.5% 20% 16%)"
  tapete-sombra: "rgb(4.9% 15% 13%)"
  grade-e-cotas: "rgb(68% 82% 74%)"
  grafite-luz: "rgb(32% 36% 37%)"
  grafite-sombra: "rgb(13% 17% 19%)"
  visor-claro: "rgb(83% 88% 70%)"
  visor-sombra: "rgb(64% 73% 50%)"
  tinta-do-visor: "rgb(11% 19% 10%)"
typography:
  medida:
    fontFamily: "SF Mono"
    fontSize: "15pt"
    fontWeight: 600
  rotulo-medida:
    fontFamily: "SF Pro"
    fontSize: "11pt"
    fontWeight: 500
rounded:
  gabinete-do-visor: "17pt"
  tela-do-visor: "9pt"
  item-de-arte: "8pt"
  miniatura: "6pt"
spacing:
  recuo-inspetor: "17pt"
  recuo-rodape: "16pt"
  margem-inferior-do-visor: "24pt"
components:
  visor-de-medidas:
    rounded: "{rounded.gabinete-do-visor}"
    height: "72pt"
    padding: "10pt 12pt"
  item-de-arte:
    rounded: "{rounded.item-de-arte}"
    padding: "6pt"
  miniatura:
    rounded: "{rounded.miniatura}"
    size: "38pt"
---

# Aparência do Cartrest

## Overview

O tapete ocupa o painel esquerdo de ponta a ponta. A arte fica no cartucho e as cotas aparecem no visor flutuante. O inspetor à direita reúne modos de prévia, artes, enquadramento e impressão, com as ações de exportação no rodapé.

## Colors

`AparenciaCartrest` acompanha o modo claro ou escuro do macOS. O verde dá ênfase à seleção da arte, aos dados principais e à ação de exportar PDF. Janela, inspetor e rodapé usam tons próprios, separados por divisores de 1 pt. Os textos correntes usam as cores semânticas do sistema.

O tapete usa um gradiente verde diagonal nos dois modos. O cartucho tem um gradiente grafite, a folha A4 é branca e o visor tem fundo verde-claro com tinta escura.

## Typography

As medidas do visor usam o estilo monoespaçado do sistema. Os cabeçalhos do inspetor, subtítulos e legendas usam `headline`, `subheadline` e `caption` do SwiftUI. Os totais usam dígitos tabulares.

## Layout

O `HSplitView` permite ajustar a divisão. A janela abre em 1180 × 790 pt, com mínimo de 800 × 610 pt. A prancheta tem mínimo de 470 pt de largura e o inspetor varia de 320 a 420 pt. O visor fica a 24 pt da borda inferior do tapete. A área de desenho reserva espaço para manter a peça e o papel acima do visor.

## Elevation & Depth

O tom diferencia as áreas do inspetor. Na prancheta, sombras separam o cartucho e a folha do tapete. O rebaixo da peça aparece em grafite escuro. O visor tem carcaça sombreada, tela rebaixada e parafusos de acabamento.

## Components

- **Prancheta.** O `Canvas` usa uma grade de 5 e 20 mm nas vistas da peça e do corte. Os traços têm 0,65 pt, com opacidades de 10% e 17%. A grade acompanha a escala do desenho e omite intervalos menores que 3 pt. A vista A4 apresenta a régua de 50 mm. As medidas da peça, do corte e da arte com sangria aparecem no visor.
- **Controles.** O seletor segmentado alterna entre peça, corte, folha A4 e a órbita 3D. Ajustes usam sliders, campos numéricos, menus e stepper do macOS. O PDF usa um botão `borderedProminent` com a cor de realce do tema. O PNG usa um botão padrão.
- **Artes.** A linha selecionada recebe preenchimento e contorno do tema. A miniatura mantém o recorte quadrado e o nome aparece em uma linha.
