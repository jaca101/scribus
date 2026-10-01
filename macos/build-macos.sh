#!/usr/bin/env bash
# Build de Scribus (master, Qt 6) en macOS Apple Silicon con Homebrew + CMake + Ninja.
#
# Uso:
#   ./build-macos.sh deps        # instala dependencias Homebrew (una vez)
#   ./build-macos.sh podofo      # compila PoDoFo en deps/podofo (Homebrew no puede instalarlo: bug openssl@4)
#   ./build-macos.sh configure   # genera build/ con CMake + Ninja
#   ./build-macos.sh build       # compila
#   ./build-macos.sh install     # instala en install/Scribus.app (necesario para ejecutar)
#   ./build-macos.sh run         # lanza el .app instalado
#   ./build-macos.sh all         # configure + build + install
#   ./build-macos.sh clean       # borra build/ e install/
#   ./build-macos.sh app         # build release autónomo en dist/Scribus.app (Qt y librerías dentro)
#   ./build-macos.sh applications # instala dist/Scribus.app en /Applications (la anterior va a la Papelera)
#
# Variables opcionales:
#   BUILD_KIND=relwithdebug|debug|release   (por defecto relwithdebug, útil para lldb)
#   JOBS=N                                   (por defecto: nº de núcleos)
#   WANT_GM=0|1                              (GraphicsMagick; por defecto 1, `app` lo desactiva)
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$HERE/../CMakeLists_Apple.cmake" ]; then
	SRC="$(cd "$HERE/.." && pwd)"   # script dentro del árbol de Scribus (macos/)
else
	SRC="$HERE/scribus"             # script junto al clon
fi
ROOT="$(dirname "$SRC")"           # build/, install/ y deps/ van junto al clon
BUILD="$ROOT/build"
APP="$ROOT/install/Scribus.app"
BUILD_KIND="${BUILD_KIND:-relwithdebug}"
PODOFO_VERSION="1.1.2"
PODOFO_SRC="$ROOT/deps/podofo-src"
PODOFO_PREFIX="$ROOT/deps/podofo"
JOBS="${JOBS:-$(sysctl -n hw.ncpu)}"
WANT_GM="${WANT_GM:-1}"
DIST="$ROOT/dist/Scribus.app"

BREW="$(brew --prefix)"

REQUIRED_FORMULAE=(
	cmake ninja pkgconf ccache
	qt                      # Qt 6 (master exige >= 6.5; Core5Compat, Svg, PrintSupport, LinguistTools incluidos)
	poppler                 # >= 24.05 fuerza C++20
	cairo little-cms2 freetype fontconfig
	harfbuzz icu4c@78       # pkg-config: harfbuzz, harfbuzz-icu, harfbuzz-subset, icu-uc
	hunspell
	jpeg-turbo libpng libtiff jpeg-xl
	boost                   # 2geomtools
	python@3.14             # plugin Scripter
)
OPTIONAL_FORMULAE=(
	graphicsmagick                                   # -DWANT_GRAPHICSMAGICK=1
	librevenge libcdr libvisio libmspub libpagemaker libfreehand  # importadores CDR/VSD/PUB/PM/FH
)

cmd_deps() {
	brew update
	brew install "${REQUIRED_FORMULAE[@]}"
	brew install "${OPTIONAL_FORMULAE[@]}" || echo "Aviso: alguna dependencia opcional falló; el build sigue siendo posible."
}

# PoDoFo (importador AI) se compila aparte: en Homebrew 7.0.7 `brew install podofo` falla siempre al
# enlazar su dependencia openssl@4 ("already locked .../openssl@3"). Se compila contra openssl@3 con
# install_name absoluto, así Scribus lo encuentra sin rpath.
cmd_podofo() {
	[ -d "$PODOFO_SRC" ] || git clone --depth 1 --branch "$PODOFO_VERSION" https://github.com/podofo/podofo.git "$PODOFO_SRC"
	cmake -S "$PODOFO_SRC" -B "$PODOFO_SRC/build" -G Ninja \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_INSTALL_PREFIX="$PODOFO_PREFIX" \
		-DCMAKE_INSTALL_NAME_DIR="$PODOFO_PREFIX/lib" \
		-DCMAKE_PREFIX_PATH="$(brew --prefix openssl@3);$BREW" \
		-DOPENSSL_ROOT_DIR="$(brew --prefix openssl@3)" \
		-DPODOFO_BUILD_LIB_ONLY=ON \
		-DPODOFO_BUILD_STATIC=OFF
	cmake --build "$PODOFO_SRC/build" -j "$JOBS"
	cmake --install "$PODOFO_SRC/build"
}

cmd_configure() {
	local qt_prefix icu_prefix py_prefix kind_flag
	qt_prefix="$(brew --prefix qt)"
	icu_prefix="$(brew --prefix icu4c@78)"
	py_prefix="$(brew --prefix python@3.14)"

	case "$BUILD_KIND" in
		debug)        kind_flag="-DWANT_DEBUG=1" ;;
		release)      kind_flag="" ;;
		relwithdebug) kind_flag="-DWANT_RELEASEWITHDEBUG=1" ;;
		*) echo "BUILD_KIND desconocido: $BUILD_KIND" >&2; exit 1 ;;
	esac

	# icu4c es keg-only: hay que exponer su .pc para harfbuzz-icu / icu-uc.
	export PKG_CONFIG_PATH="$icu_prefix/lib/pkgconfig:$BREW/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
	# CMakeLists_Dependencies.cmake *sobrescribe* la variable CMAKE_PREFIX_PATH con ${QT_PREFIX}/lib/cmake,
	# así que pasamos QT_PREFIX y además usamos la variable de *entorno* (que no se pisa).
	export CMAKE_PREFIX_PATH="$qt_prefix:$BREW"

	# En el trunk sin parchear, FindLIBPODOFO.cmake usa pkg_search_module(... REQUIRED ...): sin PoDoFo
	# el configure falla aunque sea opcional, así que se desactiva explícitamente si no está.
	# (Corregido en macos/ui-fixes, Mantis #17993; se mantiene para poder compilar el trunk tal cual.)
	local podofo_flags=(-DWITH_PODOFO=OFF)
	if [ -f "$PODOFO_PREFIX/include/podofo/podofo.h" ]; then
		podofo_flags=(-DWITH_PODOFO=ON -DLIBPODOFO_DIR_PREFIX="$PODOFO_PREFIX")
	elif brew list --versions podofo >/dev/null 2>&1; then
		podofo_flags=(-DWITH_PODOFO=ON)
	fi

	# En el trunk sin parchear, scribus/CMakeLists.txt enlaza ${GMAGICK_LIBRARIES} (solo "GraphicsMagick",
	# sin ruta): fuera de /usr/lib el linker no lo encuentra, así que añadimos su directorio.
	# (Corregido en macos/ui-fixes, Mantis #17994; inofensivo con el parche aplicado.)
	local exe_ldflags="-L$(brew --prefix graphicsmagick)/lib"

	# Nota: CMAKE_BUILD_TYPE se fuerza desde WANT_DEBUG / WANT_RELEASEWITHDEBUG; no pasarlo a mano.
	cmake -S "$SRC" -B "$BUILD" -G Ninja \
		-DQT_PREFIX="$qt_prefix" \
		-DCMAKE_INSTALL_PREFIX="$APP/Contents" \
		-DBUILD_OSX_BUNDLE=1 \
		-DWANT_OSX_SDK=1 \
		-DCMAKE_OSX_SYSROOT="$(xcrun --sdk macosx --show-sdk-path)" \
		-DPython3_EXECUTABLE="$py_prefix/bin/python3.14" \
		-DWANT_NOOSG=1 \
		-DWANT_GRAPHICSMAGICK="$WANT_GM" \
		-DWANT_CCACHE=1 \
		-DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
		"${podofo_flags[@]}" \
		-DCMAKE_EXE_LINKER_FLAGS="$exe_ldflags" \
		$kind_flag

	# compile_commands.json en la raíz del clon para clangd / sourcekit-lsp.
	[ "$BUILD" = "$ROOT/build" ] && ln -sf "$BUILD/compile_commands.json" "$SRC/compile_commands.json"
	return 0
}

cmd_build()   { cmake --build "$BUILD" -j "$JOBS"; }
cmd_install() { cmake --install "$BUILD"; }
cmd_run()     { "$APP/Contents/MacOS/Scribus" "$@"; }
cmd_clean()   { rm -rf "$BUILD" "$ROOT/install"; }

# App autónoma para uso diario: build release aparte (build-app/), sin GraphicsMagick, empaquetada con
# macdeployqt en dist/Scribus.app. GraphicsMagick queda fuera porque carga sus 96 decodificadores como
# módulos desde Homebrew, que arrastran una segunda copia de libGraphicsMagick y abortan al arrancar.
# Python (plugin Scripter) sigue viniendo de Homebrew: si faltara, solo dejaría de cargar ese plugin.
cmd_app() {
	BUILD="$ROOT/build-app"; APP="$ROOT/stage/Scribus.app"; BUILD_KIND=release; WANT_GM=0
	cmd_configure
	cmd_build
	rm -rf "$ROOT/stage"
	cmd_install
	cmd_bundle
}

cmd_bundle() {
	local plugins=()
	rm -rf "$(dirname "$DIST")"; mkdir -p "$(dirname "$DIST")"
	cp -R "$APP" "$DIST"
	while IFS= read -r f; do plugins+=("-executable=$f"); done < <(find "$DIST/Contents/lib" -name '*.so' -o -name '*.dylib' | sort)
	"$(brew --prefix qt)/bin/macdeployqt" "$DIST" "${plugins[@]}" \
		-libpath="$PODOFO_PREFIX/lib" -libpath="$BREW/lib" -libpath="$BREW/Frameworks" \
		-no-codesign -verbose=1 > "$ROOT/dist/macdeployqt.log" 2>&1 || true
	# Plugins de Qt cuyas dependencias no se empaquetan (teclado virtual, PDF); Scribus no los usa.
	rm -f "$DIST/Contents/PlugIns/platforminputcontexts/libqtvirtualkeyboardplugin.dylib" \
		"$DIST/Contents/PlugIns/imageformats/libqpdf.dylib"
	rmdir "$DIST/Contents/PlugIns/platforminputcontexts" 2>/dev/null || true
	# Quitar rpaths del build (Homebrew, rutas relativas) y buscar solo dentro del bundle.
	while IFS= read -r f; do
		file "$f" | grep -q Mach-O || continue
		for rp in $(otool -l "$f" | awk '/LC_RPATH/{getline; getline; print $2}' | grep -E "^$BREW|^/Users|^lib\$" || true); do
			install_name_tool -delete_rpath "$rp" "$f" 2>/dev/null || true
		done
	done < <(find "$DIST/Contents" -type f)
	install_name_tool -add_rpath @executable_path/../Frameworks "$DIST/Contents/MacOS/Scribus" 2>/dev/null
	codesign --force --deep --sign - "$DIST" >/dev/null 2>&1
	codesign --verify --deep --strict "$DIST"
	echo "App autónoma lista: $DIST"
}

cmd_applications() {
	[ -d "$DIST" ] || { echo "Primero: $0 app" >&2; exit 1; }
	if [ -d /Applications/Scribus.app ]; then
		osascript -e 'tell application "Finder" to delete POSIX file "/Applications/Scribus.app"' >/dev/null
	fi
	cp -R "$DIST" /Applications/Scribus.app
	/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/Scribus.app
	echo "Instalado en /Applications/Scribus.app"
}

case "${1:-all}" in
	deps)      cmd_deps ;;
	podofo)    cmd_podofo ;;
	configure) cmd_configure ;;
	build)     cmd_build ;;
	install)   cmd_install ;;
	run)       shift; cmd_run "$@" ;;
	all)       cmd_configure; cmd_build; cmd_install ;;
	clean)     cmd_clean ;;
	app)       cmd_app ;;
	applications) cmd_applications ;;
	*) sed -n '2,21p' "$0"; exit 1 ;;
esac
