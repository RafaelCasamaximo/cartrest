# A configuração grava o layout do Finder no volume durante a montagem do DMG.
# As cotas de ícones e janela acompanham a arte de fundo em fundo.swift.

format = "UDZO"
files = [defines["app"]]
symlinks = {"Aplicativos": "/Applications"}
icon = defines["icon"]
background = defines["fundo"]

window_rect = ((240, 180), (640, 400))
show_toolbar = False
show_sidebar = False
show_pathbar = False
show_status_bar = False
default_view = "icon-view"
arrange_by = None
icon_locations = {"Cartrest.app": (174, 229), "Aplicativos": (466, 229)}
icon_size = 92
text_size = 13
