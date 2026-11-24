# Modelo 3D do Cartrest

O porta-copos tem **100 × 106,06 × 6 mm** (largura, altura e espessura). A face frontal mantém a proporção aproximada de 33 × 35 mm do cartucho Nintendo DS. A espessura é própria para o porta-copos. A base é plana, e a face tem a seta em baixo-relevo e o rebaixo para a arte.

| Peça | Largura × altura | Detalhe |
| --- | --- | --- |
| Porta-copos | 100 × 106,06 mm | Espessura de 6 mm |
| Rebaixo | 82,6 × 87,2 mm | Profundidade de 0,6 mm |
| Adesivo no corte | 81,8 × 86,4 mm | Folga nominal de 0,4 mm por lado, com chanfro de 7,5 mm no canto inferior esquerdo |
| Cupom de encaixe | 36 × 28 mm | Rebaixo de 26 × 20 × 0,6 mm |

## Fatiamento na Creality K2 SE

1. Importe `cartrest-ds-100mm.stl` no Creality Print em milímetros e a **100%**, com a face do adesivo para cima. A K2 SE tem volume útil de 220 × 215 × 245 mm e aceita PLA. [Especificações oficiais da Creality](https://www.creality.com/support/k2-se).
2. Se estiver com o bico de 0,4 mm, comece no preset **0,20 mm Standard** e use o perfil PLA do fabricante do filamento ou **Generic PLA**. Para o primeiro teste, use 3 paredes, 5 camadas superiores, 4 inferiores e 15–20% de preenchimento. A peça pode ser fatiada sem suportes. [Guia do Creality Print](https://www.creality.com/help/help-creality-print-quick-start-guide).
3. Opcionalmente, imprima primeiro `cartrest-cupom-encaixe.stl`. Para testar o canto e a folga, corte um retângulo de papel de 25,2 × 19,2 mm com raio de 3,5 mm nos três cantos arredondados e chanfro de 7,5 mm no canto inferior esquerdo. Depois teste a etiqueta inteira em papel comum a 100% no porta-copos antes de gastar vinil.
4. Aplique o adesivo na superfície limpa e seca. Use o PLA para copos frios ou à temperatura ambiente. Bases muito quentes e lava-louças podem deformar a peça ou prejudicar a colagem. [Guia de PLA da Creality](https://uatstore.creality.com/blogs/basics/pla-filament-guide-properties-settings).

## Outras larguras

No Terminal, a partir da pasta do projeto, execute o gerador com Python 3. O exemplo abaixo cria outra pasta, `modelo/90mm/`, com um porta-copos de 90 × 95,454 × 6 mm, a etiqueta de 73,62 × 77,76 mm e as duas malhas correspondentes. Ele preserva a espessura da peça e as profundidades dos rebaixos.

```sh
python3 modelo/gerar_modelos.py --largura 90
```

O `dimensoes.json` da pasta gerada registra as cotas em milímetros. As origens `x` e `y` do adesivo e do rebaixo são medidas do topo esquerdo da face. Se preferir escalar o STL padrão no fatiador, aplique o mesmo fator nos eixos X e Y, deixe Z em 100% e use o mesmo fator nas dimensões e nos cantos do adesivo.

O gerador aceita larguras de **60 a 180 mm**. Use uma pasta por largura para manter a peça, o cupom e as cotas correspondentes juntos. Para escolher a pasta, passe `--saida`.

## Cotas compartilhadas com o editor

O conjunto `DIMENSIONS` no gerador é a fonte das cotas. A execução padrão recria os dois STLs e o JSON no mesmo diretório. O build copia esse JSON para os recursos do aplicativo. O editor o usa para desenhar o encaixe e definir o contorno de corte do PDF. [Gerador](gerar_modelos.py) · [Cotas padrão](dimensoes.json)

Na vista frontal, X cresce à direita e Y para baixo. Ao gerar o STL, o script inverte Y para preservar a orientação do chanfro e da seta vistos de cima. O STL usa arcos aproximados por segmentos, com base plana em Z = 0. Na escala de 100 mm, a folga de 0,4 mm é medida perpendicularmente à borda, inclusive na diagonal do chanfro.

Para conferir a reprodução do conjunto padrão, regenere os três arquivos em uma pasta de saída e compare com os arquivos de `modelo/`.

```sh
python3 modelo/gerar_modelos.py --saida dist/modelo-100mm
cmp modelo/dimensoes.json dist/modelo-100mm/dimensoes.json
cmp modelo/cartrest-ds-100mm.stl dist/modelo-100mm/cartrest-ds-100mm.stl
cmp modelo/cartrest-cupom-encaixe.stl dist/modelo-100mm/cartrest-cupom-encaixe.stl
```

## Referências de forma e alternativas

- Uma medição com paquímetro do cartucho DS registrou 32,93 mm de largura, 34,96 mm de altura e 3,79 mm de espessura. O mesmo autor mediu 34,90 mm de largura na parte mais larga do modelo 3DS, que tem uma aba lateral. [Medição publicada pelo autor](https://www.reddit.com/r/gamecollecting/comments/23stkf/q_dimensions_for_game_cartridges/#:~:text=DS%3A%2034.96).
- As vistas da Nintendo mostram as diferenças entre os cantos do corpo. A foto frontal de Derrick Rossignol mostra o chanfro inferior esquerdo no rótulo e a seta de inserção na borda. [Vistas da patente da Nintendo](https://patents.google.com/patent/USD536382S1/en) · [Foto frontal](https://commons.wikimedia.org/wiki/File:Nintendo_DS_game_card.jpg).
- A Retroid anuncia 27 × 28,5 mm para suas etiquetas de reposição. Esse tamanho foi a referência para o adesivo ampliado. [Etiqueta DS da Retroid](https://retroid.nl/game-labels/nintendo-ds/).
- O **Fun Cartridge** de AF_Inventions é um pacote pago que inclui `FUN CARTRIDGE - DS - COASTER.STL`. O criador oferece licença comercial à parte. [Arquivos na Cults](https://cults3d.com/en/3d-model/game/fun-cartridge-keychain-coasters-tray-more/makes) · [Termos do autor no Thangs](https://thangs.com/prints/designer/af_inventions/3d-model/FUN%20CARTRIDGE%20%7C%20KEYCHAIN%2C%20COASTERS%2C%20TRAY%20%26%20MORE-1541080).
- O **Nintendo DS dummy cartridge**, de magu, é um STL gratuito de 33 × 35 × 3,75 mm feito para tampar o Slot-1. É uma referência de tamanho real. [Modelo publicado pelo autor](https://cults3d.com/en/3d-model/gadget/nintendo-ds-dummy-cartridge-ds-dsi-3ds-2ds).

Os STLs do Cartrest foram gerados do zero. A verificação digital confirmou uma malha fechada por peça e conferiu as cotas das 30 seções em passos de 0,20 mm. O cupom permite confirmar a folga na sua impressora e com o seu vinil.
