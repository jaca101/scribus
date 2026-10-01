# Scribus en macOS (Apple Silicon): entorno y mapa del código

Clon: `scribus/` (rama `master` @ `3ed5222d9`, versión **1.7.4svn**, **solo Qt 6 ≥ 6.5**).
Para Qt 5 / estabilidad: `git -C scribus switch Version16x` (1.6.x, admite Qt 5.14+ o Qt 6).

Máquina: macOS 26.6 (darwin25 → CMake la detecta como `APPLE_25_00_X`, "Tahoe"), Xcode / Apple clang 21, Homebrew 7.

---

## 1. Dependencias (Homebrew)

| Dependencia | Fórmula | ¿Instalada al empezar? | Notas |
|---|---|---|---|
| CMake ≥ 3.16, Ninja | `cmake ninja` | ❌ | |
| pkg-config | `pkgconf` | ✅ | |
| Qt 6 (Core, Core5Compat, Gui, Widgets, Network, OpenGL(Widgets), PrintSupport, Xml, Svg, LinguistTools) | `qt` (6.11) | ❌ | Se pasa con `-DQT_PREFIX` (ver nota abajo) |
| Poppler (REQUIRED) | `poppler` (26.x) | ❌ | ≥ 24.05 hace que CMake suba a **C++20** |
| Cairo, LittleCMS2, FreeType, Fontconfig | `cairo little-cms2 freetype fontconfig` | ✅ | |
| HarfBuzz + harfbuzz-icu / -subset, ICU | `harfbuzz icu4c@78` | ✅ | `icu4c@78` es keg-only → `PKG_CONFIG_PATH` |
| Hunspell ≥ 1.6 (REQUIRED) | `hunspell` | ❌ | |
| JPEG, PNG ≥ 1.6, TIFF, JPEG XL | `jpeg-turbo libpng libtiff jpeg-xl` | ✅ | |
| LibXml2 ≥ 2.6 | SDK de macOS | ✅ | No hace falta la fórmula |
| ZLIB, CUPS | SDK de macOS | ✅ | |
| Python 3 (Interpreter + Development) | `python@3.14` | ✅ | Se fija con `-DPython3_EXECUTABLE` para no coger el de Xcode |
| Boost (opcional, 2geomtools) | `boost` | ❌ | |
| PoDoFo (opcional, importador AI) | `podofo` (1.1) | ❌ | La API 1.x está soportada (`pdf_analyzer.cpp:33`) |
| GraphicsMagick (opcional) | `graphicsmagick` | ❌ | `-DWANT_GRAPHICSMAGICK=1` |
| librevenge + libcdr/libvisio/libmspub/libpagemaker/libfreehand (opcional) | mismas fórmulas | ❌ | `libqxp` y `libzmf` no tienen fórmula → esos importadores no se compilan |
| OpenSceneGraph (3D PDF) | — | — | Se desactiva con `-DWANT_NOOSG=1` |

**Particularidades del sistema de build que hay que conocer**
- `CMakeLists_Dependencies.cmake:69` **sobrescribe** la variable `CMAKE_PREFIX_PATH` con `${QT_PREFIX}/lib/cmake`. Hay que pasar `-DQT_PREFIX=$(brew --prefix qt)` y usar la variable de *entorno* `CMAKE_PREFIX_PATH`.
- `CMAKE_BUILD_TYPE` se fuerza (`CMakeLists.txt:400-408`): usa `-DWANT_DEBUG=1` o `-DWANT_RELEASEWITHDEBUG=1`, no `-DCMAKE_BUILD_TYPE`.
- `BUILD_OSX_BUNDLE` vale `ON` por defecto en Apple; la instalación va a `<prefix>/Scribus.app/Contents`, y el binario queda en `Contents/MacOS/Scribus`. **Hay que hacer `install`** para ejecutar (recursos, plugins e iconos se resuelven con rutas del bundle).
- El `README.MacOSX` del repo está desactualizado (MacPorts/SVN); este flujo lo reemplaza.

## 2. Build

Script: [`build-macos.sh`](build-macos.sh). En el fork está en `macos/build-macos.sh`. Funciona tanto dentro del árbol de Scribus como junto al clon; en los dos casos `build/`, `install/` y `deps/` se crean al lado del clon.

```bash
./build-macos.sh deps
```
```bash
./build-macos.sh all
```
```bash
./build-macos.sh run
```

`BUILD_KIND=debug|relwithdebug|release` (por defecto `relwithdebug`). También genera `scribus/compile_commands.json` para clangd/Xcode.

### Validación (2026-10-01, `master` @ `3ed5222d9`, sin modificar)
- Configure y build con Ninja **OK**: 0 errores de compilación. El bundle `install/Scribus.app` (arm64, 219 MB, 67 plugins en `Contents/lib`) no tiene dylibs sin resolver.
- Headless: `Scribus --no-gui -py script.py` crea un documento con texto, rectángulo y marco de imagen y exporta un PDF válido (Poppler lee el texto con acentos; ArialMT embebida como subset).
- GUI: arranca y se mantiene estable en reposo (unos 250 MB de RSS) sin errores en el log.

### Problemas del build original en macOS/Homebrew
Los puntos 1-3 están **corregidos en la rama** (commits `22ace552a`, `47059e7ab`, `76b178e76`; parches 0007-0009 en [`patches/`](patches/)). Verificado con builds limpios sin los rodeos del script. `build-macos.sh` mantiene los rodeos para poder compilar también el trunk sin parchear.
1. `cmake/modules/FindLIBPODOFO.cmake:21` usa `pkg_search_module(... REQUIRED ...)`, así que PoDoFo, "opcional", rompe el configure si no está instalado. El script lo esquiva con `-DWITH_PODOFO=OFF`.
2. `scribus/plugins/import/ai/CMakeLists.txt:4` añade `${LIBPODOFO_INCLUDE_DIR}` sin `if(HAVE_PODOFO)`. Con un valor `-NOTFOUND` en caché, el generate falla; hay que borrar `build/`.
3. `scribus/CMakeLists.txt:232` enlaza `${GMAGICK_LIBRARIES}` (solo el nombre) en vez de `${GMAGICK_LINK_LIBRARIES}` (ruta completa), así que el linker falla fuera de `/usr/lib`. El script lo esquiva con `-DCMAKE_EXE_LINKER_FLAGS=-L<graphicsmagick>/lib`.
4. El objetivo de despliegue por defecto es macOS 12 y las librerías de Homebrew son de macOS 14/26: el linker da muchos warnings, sin efecto en local. Se silencian con `-DOSXMINVER=26.0` (provoca una recompilación completa).

### Estado de Homebrew en esta máquina
- `brew install podofo` falla siempre en Homebrew 7.0.7: al instalar `openssl@4` se queda bloqueado `openssl@3` y el keg se deja a medias (`4.0.3` + `4.0.3.tmp`). Se ha limpiado con `brew uninstall --ignore-dependencies openssl@4`, así que `openssl@3` queda intacto.
- En su lugar, `./build-macos.sh podofo` compila **PoDoFo 1.1.2** desde el repo oficial contra `openssl@3` y lo instala en `deps/podofo`, con `install_name` absoluto. `configure` lo detecta solo (`-DLIBPODOFO_DIR_PREFIX`). Comprobado: `HAVE_PODOFO 1`, y tanto `Scribus` como `libimportai.so` enlazan contra `deps/podofo/lib/libpodofo.4.dylib`.

---

## 3. Bug: tras editar texto, arrastrar una imagen mueve su contenido y no el marco

### Causa raíz
`scribus/canvasmode_edit.cpp:603-645`: `CanvasMode_Edit::mousePressEvent`. Con un marco de texto en modo edición (`modeEdit`), un clic **fuera** de él (`frameHitTest < 0`) llama a `SeleItem()` y, si el nuevo ítem es un **marco de texto o de imagen**, se queda en `modeEdit` (`wantNormal = false`):

```cpp
if ((currItem->isTextFrame()) || (currItem->isImageFrame()))
{
    m_view->requestMode(modeEdit);   // ← la imagen hereda el modo "editar contenido"
    wantNormal = false;
}
```

Después, `CanvasMode_Edit::mouseMoveEvent` (`canvasmode_edit.cpp:443-467`) trata cualquier arrastre sobre un marco de imagen en `modeEdit` como desplazamiento del contenido: `currItem->moveImageInFrame(...)` (línea 463), es decir, cambia `imageXOffset/imageYOffset` en lugar de mover el marco.

El mismo patrón aparece en la segunda rama (`canvasmode_edit.cpp:734-744`) cuando el ítem activo no es de texto.

### Corrección aplicada (commit `cea548752`, Mantis #17989)
Solo los marcos de **texto** mantienen `modeEdit` al hacer clic desde otro marco. Los de imagen siguen el mismo camino que las formas: pasan a `modeNormal` y el clic se reenvía a `CanvasMode_Normal`, así que el arrastre mueve el marco. La edición del contenido de la imagen sigue disponible con doble clic (`canvasmode_normal.cpp:184-210`).

```diff
-					if ((currItem->isTextFrame()) || (currItem->isImageFrame()))
+					// Only text frames keep content editing when clicked from another frame.
+					// Image frames go back to normal mode so a drag moves the frame rather than
+					// the image offset; image content editing is still entered by double click.
+					if (currItem->isTextFrame())
```
La segunda rama con el mismo patrón (`canvasmode_edit.cpp:737`) solo se activa con marcos bloqueados o con clics dentro del marco en edición; no se ha tocado. Verificado a mano en la GUI.

Archivos relacionados con la máquina de estados:
- `scribusview.cpp:428`: `ScribusView::requestMode()` (cambia el `CanvasMode` activo; los submodos están en `appmodes.h` / `canvasmode.h`).
- `canvasmode.cpp`: base común (`commonMouseMove`, selección, dibujo de controles).
- `canvasmode_normal.cpp`: selección, movimiento y redimensionado de marcos; el doble clic entra en `modeEdit` y `modeEditClip`.
- `canvasmode_edit.cpp`: edición de texto e imagen (offset, rotación de la imagen con Shift).
- `canvasgesture_resize.cpp`, `canvasgesture_rulermove.cpp`: gestos.
- `canvas.cpp`: `frameHitTest`, `itemUnderCursor`, pintado.

---

## 4. Toolbars y modo oscuro en macOS

| Pieza | Ubicación | Qué hace |
|---|---|---|
| `ScToolBar` (base `QToolBar`) | `ui/sctoolbar.{h,cpp}` | Icono fijo de 20 px, visibilidad persistida en prefs |
| Toolbars concretas | `ui/{file,edit,mode,pdf,view}toolbar.cpp` | |
| Creación | `scribus.cpp:607` `initToolBars()` | `addToolBar`; no se usa `setUnifiedTitleAndToolBarOnMac` |
| Hoja de estilo | `scribus.cpp:630` `setStyleSheet()` + `scribus/scribus.css` | Aplica **toda** la hoja (incl. reglas ADS con `palette(...)`) a cada toolbar |
| Reacción al cambio claro/oscuro | `scribus.cpp:498` | Reaplica el stylesheet al recibir `colorSchemeChanged` ("THIS IS A WORKAROUND!") |
| Recoloreado de iconos SVG | `iconmanager.cpp:61, 127-136, 410` | Tiñe los iconos con `palette().windowText()` al reconstruir la caché |
| Estilo y tema | `ui/factories/scribusproxystyle.cpp:253, 271` | `QProxyStyle` sobre el estilo nativo; tema mediante `QStyleHints::setColorScheme` |
| Tema forzado al arrancar | `scribuscore.cpp:262-270` | |

**Conclusión (verificada el 2026-10-01):**
- El fallo reportado (iconos invisibles y barras recogidas tras `»`) se reproduce en **Scribus 1.6.6** oficial con macOS en modo oscuro. Su juego de iconos por defecto, «Scribus 1.5.1», es de PNG gris oscuro con color fijo; además, los botones que no caben se agrupan en el menú de desbordamiento.
- En **master (1.7)** está resuelto. El juego por defecto `1.7.0` es SVG y se recolorea con la paleta (traza: iconos `#ffffff` sobre `#1e1e1e` en modo oscuro). Además, `prefsmanager.cpp:2076-2078` sustituye siempre por `1.7.0` cualquier juego `1.5.x` heredado. No hace falta parche en esta rama.
- Descartadas las hipótesis iniciales (stylesheet en `QToolBar`, carrera paleta/esquema): no se reproducen.
- **Corregido (commit `248909819`):** el filtro de `ScribusProxyStyle` consumía siempre `QEvent::ThemeChange` en `qApp` (`scribusproxystyle.cpp:240-249`). En Qt 6.11, `processThemeChanged()` envía `ThemeChange` solo a `qApp`, y `QGuiApplication::event()` lo reenvía a todas las ventanas para que los widgets se re-pulan. Prueba con traza temporal: con el código original las ventanas lo recibían 0 veces; con el arreglo, 4 por cada cambio de apariencia. En macOS no se aprecia diferencia visual.
- **Fallos visuales que ya existían** (iguales con y sin el arreglo, verificado con capturas):
  1. **Corregido (commit `fac896eef`):** al pasar a claro, la lista de miniaturas de «Páginas del documento» y el área de trabajo del lienzo («scratch space») se quedaban oscuras. Las dos usan `displayPrefs.scratchColor`. #17952 solo lo actualizaba al cambiar el tema desde Preferencias: cuando el cambio viene del sistema, Qt ya ha sustituido la paleta al llegar al filtro y no se puede reconocer el color por defecto. Ahora el manejador de `PaletteChange` de la ventana principal recuerda el color anterior, actualiza `scratchColor` si era el de por defecto y repinta la cuadrícula de páginas y las vistas.
     - Efecto secundario detectado y corregido en el mismo commit: tras arrancar en oscuro y pasar a claro, la barra de título del documento se quedaba oscura. La paleta de la subventana era correcta (verificado con traza), pero `QMdiSubWindow` guarda la de la barra (`titleBarPalette`) en su último `PaletteChange`. Se le reenvía `PaletteChange`.
     - Verificado arrancando en claro y en oscuro, cambiando en ambos sentidos, con CPU al 0 %.
  2. **Corregido (commit `f23ebf2d9`):** al volver a oscuro, las pestañas activas de los paneles ADS salían grises. Causa real, verificada en el código de Qt 6.11: `ApplicationPaletteChange` llega a la ventana principal como evento **encolado** (a las demás ventanas se envía de forma síncrona solo si no son de nivel superior). El filtro de ADS sobre esa ventana recarga su hoja de estilos y pisa la de Scribus, que se había aplicado antes desde `colorSchemeChanged` y con la paleta antigua. Un primer intento (encolar el `setStyleSheet()` desde ese lambda) **no funcionó**, porque se ejecutaba antes que la recarga de ADS. El arreglo bueno reaplica la hoja desde `ScribusMainWindow::changeEvent(PaletteChange)`, que llega justo después de que ADS haya actuado. Verificado con la secuencia oscuro → claro → oscuro: pestañas como en el arranque y CPU al 0 %.
- Fallo de upstream encontrado de paso (**corregido, commit `071980d88`**): con `--prefs <dir>`, `PrefsManager::copyOldAppConfigAndData()` **movía** (no copiaba) `scribus150.rc` y `prefs150.xml` de la 1.6 desde `~/Library/Preferences/Scribus/`, de modo que la 1.6 perdía su configuración. Ahora, con `--prefs`, los ficheros heredados se copian. Verificado en un `HOME` aislado: el origen queda intacto y el perfil nuevo recibe copias idénticas.

### Ruido de diccionarios (corregido, commit `62835bfbe`)
`HunspellManager` (`spellcheckfunctions.cpp`) no cacheaba los diccionarios ausentes: en cada pasada del corrector volvía a buscar en disco y repetía `Dictionary files not found for language`. Ahora recuerda los fallos durante 30 s y avisa una sola vez por idioma. Medido: 33 avisos antes y 1 después en una sesión equivalente.

---

## 5. Separación motor ↔ GUI (de cara a C++ Interop con Swift)

**Situación actual: un monolito.**
- `scribus/CMakeLists.txt:151-176`: todo el núcleo (`SCRIBUS_SOURCES`, texto, estilos, colormgmt, fonts, desaxe) se compila en un **`add_executable`** con `ENABLE_EXPORTS`. Los plugins (`.so`/`.dylib`) enlazan contra el ejecutable. **No hay una `libscribus-core`.**
- `ScribusDoc` (`scribusdoc.h`, ~19 k líneas en el `.cpp`) es un `QObject` con punteros a `ScribusMainWindow* m_ScMW` y `ScribusView* m_View` (`scribusdoc.h:125-127, 1377-1378`); `scribusdoc.cpp` tiene unas 113 referencias a GUI (`m_ScMW`, `ScribusView`, `QMessageBox`, `qApp`…).
- `PageItem` (`pageitem.h`) incluye `<QWidget>`, `<QMenu>` y `<QKeyEvent>`; hay pocas referencias directas a GUI en el `.cpp` (unas 8, más 3 en imagen y 2 en texto), pero toda la API usa tipos Qt (`QString`, `QList`, `QTransform`, señales).
- Existe un modo headless: `--no-gui` (`scribusapp.cpp:65`) y `ScCore->usingGUI()`; el plugin **Scripter** (`plugins/scriptplugin/cmd*.cpp`) es, de facto, la API de alto nivel más limpia del motor (crear docs y marcos, propiedades, exportar PDF).
- Render: `ScPainter` (`scpainter.h`, backend Cairo) es independiente de los widgets y puede dibujar en un `cairo_surface` o `QImage`, una base viable para un `NSView`/`CALayer`.

**Implicaciones para Swift/AppKit**
- Swift C++ Interop no importa bien clases `QObject` con moc/señales, ni tipos Qt complejos. La vía realista es una **fachada C++ fina** (o `extern "C"`) con tipos POD/`std::string` sobre `ScribusDoc`/`PageItem`/`ScPainter`, expuesta mediante un modulemap.
- Paso previo necesario: extraer el núcleo a una **librería estática/dinámica** (`add_library(scribus-core ...)`) y dejar el `add_executable` como GUI Qt. El principal obstáculo es cortar las dependencias `ScribusDoc → ScribusMainWindow/ScribusView` (diálogos, refrescos, undo vinculado a la vista).
- Hace falta un `QCoreApplication`/`QGuiApplication` vivo en el proceso (fuentes, `PrefsManager`, `ScPaths`, plugins de import/export). Conviene arrancar el motor como hace `--no-gui` (`ScribusCore::init` sin GUI).

---

## 6. Envío upstream
Los nueve parches están en [`patches/`](patches/) (contra trunk r27875), con los textos de los tickets en [`patches/TICKETS.md`](patches/TICKETS.md). El canal oficial es bugs.scribus.net (Mantis): un ticket por fallo, con el parche adjunto (según `README.md`). Enviados el 2026-10-01:

| Mantis | Fallo | Commits |
|---|---|---|
| #17988 | Cambio claro/oscuro del sistema en macOS | `248909819`, `f23ebf2d9`, `fac896eef` |
| #17989 | Arrastre de imagen tras editar texto | `cea548752` |
| #17990 | Aviso de diccionario repetido | `62835bfbe` |
| #17992 | `--prefs` mueve las preferencias de la 1.5/1.6 (#17991 es un duplicado sin adjunto) | `071980d88` |
| #17993 | PoDoFo opcional que en la práctica es obligatorio | `22ace552a`, `47059e7ab` |
| #17994 | GraphicsMagick no enlaza fuera de `/usr/lib` | `76b178e76` |
