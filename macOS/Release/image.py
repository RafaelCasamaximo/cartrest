# dmgbuild stores the Finder layout on the mounted image during packaging.
# The window and icon coordinates match the artwork in background.swift.

format = "UDZO"
files = [defines["app"]]
symlinks = {"Applications": "/Applications"}
icon = defines["icon"]
background = defines["background"]

window_rect = ((240, 180), (640, 400))
show_toolbar = False
show_sidebar = False
show_pathbar = False
show_status_bar = False
default_view = "icon-view"
arrange_by = None
icon_locations = {"Cartrest.app": (174, 229), "Applications": (466, 229)}
icon_size = 92
text_size = 13
