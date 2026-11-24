#!/bin/bash
set -euo pipefail

pasta_mac="$(cd -- "$(dirname -- "$0")" && pwd -P)"
projeto="$(dirname -- "$pasta_mac")"
fontes="$pasta_mac/Release"
saida="${CARTREST_DIST_DIR:-$projeto/dist}"

if [[ ${1:-} == -h || ${1:-} == --help ]]; then
  printf 'Uso: %s [X.Y.Z]\n' "$0"
  exit 0
fi

versao="${1:-$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - "$pasta_mac/Info.plist")}"
if [[ $# -gt 1 || ! "$versao" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  printf 'Informe a versão no formato X.Y.Z.\n' >&2
  exit 2
fi
identidade="${CARTREST_CODESIGN_IDENTITY:--}"
perfil="${CARTREST_NOTARY_PROFILE:-}"
if [[ -n "$perfil" && "$identidade" == - ]]; then
  printf 'A notarização requer CARTREST_CODESIGN_IDENTITY com uma identidade Developer ID Application.\n' >&2
  exit 2
fi

/bin/mkdir -p "$saida"
saida="$(cd -- "$saida" && pwd -P)"
nome="Cartrest-$versao-macOS-universal.dmg"
# Uma versão é publicada por vez para manter a imagem e seu checksum lado a lado.
trava="$saida/.$nome.lock"
if ! /bin/mkdir "$trava" 2>/dev/null; then
  printf 'A pasta de saída já tem um empacotamento reservado para a versão %s.\n' "$versao" >&2
  exit 1
fi
temporario=""
limpar() {
  if [[ -n "$temporario" ]]; then
    /bin/rm -rf -- "$temporario"
  fi
  /bin/rmdir -- "$trava"
}
trap limpar EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
for arquivo in "$saida/$nome" "$saida/$nome.sha256"; do
  if [[ -L "$arquivo" || ( -e "$arquivo" && ! -f "$arquivo" ) ]]; then
    printf 'Caminho de saída ocupado: %s\n' "$arquivo" >&2
    exit 1
  fi
done
temporario="$(/usr/bin/mktemp -d "$saida/.cartrest-release.XXXXXX")"

# Reutilize o ambiente do empacotador quando já houver uma instalação isolada.
# No fluxo padrão, as ferramentas de layout ficam no ambiente temporário do release.
python="${CARTREST_DMG_PYTHON:-$temporario/venv/bin/python}"
if [[ -z "${CARTREST_DMG_PYTHON:-}" ]]; then
  python3 -m venv "$temporario/venv"
  "$python" -m pip install --disable-pip-version-check --only-binary :all: -r "$fontes/requirements.txt"
fi

app="$temporario/Cartrest.app"
"$pasta_mac/compilar.sh" --release --versao "$versao" --saida "$app"
/usr/bin/xcrun swift "$fontes/fundo.swift" "$temporario"

# UDRW é usado durante a gravação do layout. O resultado é um UDZO somente leitura.
# O arquivo de configurações recebe as referências à imagem, ao bundle e ao ícone.
dmg="$temporario/$nome"
"$python" -m dmgbuild -s "$fontes/imagem.py" \
  -D "app=$app" -D "icon=$pasta_mac/Cartrest.icns" -D "fundo=$temporario/fundo.png" \
  Cartrest "$dmg"

if [[ "$identidade" != - ]]; then
  /usr/bin/codesign --sign "$identidade" --timestamp --identifier local.cartrest.editor.dmg "$dmg"
  /usr/bin/codesign --verify --strict "$dmg"
fi
if [[ -n "$perfil" ]]; then
  # A Apple avalia o contêiner que será distribuído. Grave o tíquete antes do checksum.
  relatorio="$temporario/notarizacao.json"
  /usr/bin/xcrun notarytool submit "$dmg" --keychain-profile "$perfil" --wait --output-format json > "$relatorio"
  if [[ "$(/usr/bin/plutil -extract status raw -o - "$relatorio")" != Accepted ]]; then
    cat "$relatorio" >&2
    exit 1
  fi
  /usr/bin/xcrun stapler staple "$dmg"
  /usr/bin/xcrun stapler validate "$dmg"
fi

/usr/bin/hdiutil verify -quiet "$dmg"
(
  cd -- "$temporario"
  /usr/bin/shasum -a 256 "$nome" > "$nome.sha256"
)
# Mova apenas a imagem verificada. As duas saídas estão na mesma unidade do staging.
/bin/mv -f -- "$dmg" "$saida/$nome"
/bin/mv -f -- "$temporario/$nome.sha256" "$saida/$nome.sha256"

printf '\nInstalador pronto em %s\n' "$saida/$nome"
printf 'Checksum SHA-256 em %s\n' "$saida/$nome.sha256"
