# Bloom

**Drag a file, tap a key, drop it on a petal.**
Convert, crop, compress, inspect and share files on your Mac, offline, from a glass wheel that
opens at the pointer.

- **Free and open source** (MIT). No account, no trial, no in-app purchase.
- **Nothing to allow.** The wheel works without Accessibility or Input Monitoring permission.
- **Never touches the network.** There's no network code, and a test fails if networking APIs get linked in.
- **Native.** Swift and Apple's own frameworks (ImageIO, AVFoundation, PDFKit, Vision), Liquid Glass on macOS 26.

## The wheel

Start dragging files anywhere, in Finder or on the desktop, and **tap** a key:

| Key | Ring | What's on it |
|---|---|---|
| ⇧ Shift | **Convert** | The formats these files can become: JPG, PNG, HEIC, PDF, DOCX… |
| ⌘ Command | **Tools** | Resize, crop, rotate, compress, remove background or metadata, get text, archive |
| ⌃ Control | **Actions** | Share, metadata, float on a shelf, copy, move, copy path, open in Terminal |

- Drop on a petal to run it, or in the middle to cancel. Petals marked **›** are groups: rest on one and its options fan out around it.
- **Scroll** or tap another key to switch rings. The keys are yours to choose in Settings.
- Results are saved **next to the original**, named the way Finder would (`photo.jpg`, `photo 2.jpg`, `photo (square).heic`). Nothing is overwritten, and the original never changes.

### Styles

- **Petals** (default): a clear glass disc with eight separate glass petals, extensions as
  labels, a centre capsule that names what the drop will do, and a sky-blue highlight
  (burgundy or orange in Settings).
- **Classic**: one glass disc with thin dividers.

**Sound and haptic feedback** plays a short sound and taps the trackpad as the pointer reaches
a petal. Choose the sound, or turn it off, in Settings › Wheel.

## What it handles

- **Images:** JPEG, PNG, HEIC, AVIF, TIFF, GIF, PDF, BMP, JPEG 2000, ICNS, ICO, PSD, TGA; reads WebP, EXR and SVG too. Resize, crop, rotate, fit under 1–25 MB, compress, remove the background (macOS 14+), remove metadata, recognize text, combine into a PDF.
- **Video and audio:** MP4 (H.264, HEVC), MOV, ProRes, M4V, GIF, a still frame; M4A, WAV, AIFF, FLAC, AAC, CAF. Compress, resize, remove audio or metadata.
- **Documents and PDFs:** plain text, RTF, HTML, Word, OpenDocument, PDF; PDF to text or images; merge, split, compress, recognize text.
- **Archives:** ZIP, TAR.GZ, TAR.XZ, 7Z, Apple Archive: make, extract, convert.

Formats that need third-party encoders (writing WebP, JPEG XL, MP3, Ogg, WebM, MKV) aren't included.

**Other ways in:** drop files on the menu bar icon, **Services › Convert with Bloom…**, the Finder
Quick Action, **Open With**, and the Shortcuts actions **Convert File**, **Convert to JPEG**,
**Compress** and **Convert to PDF**.

## Command line

```bash
bloom list photo.heic                 # what this file can become
bloom convert --to image.jpeg *.heic  # results go next to each original
bloom formats                         # every conversion and whether this Mac can do it
```

## Install

Bloom isn't notarized yet, so build it yourself. You need macOS 13 or later on Apple silicon
and Xcode 26 or later.

```bash
git clone https://github.com/astmirzhan/Bloom.git
cd Bloom
make install-local
```

This builds a Release copy, signs it for your Mac, installs it to `/Applications/Bloom.app`,
links the `bloom` command into your Homebrew `bin` and opens the app.

To uninstall, quit Bloom from the menu bar, delete `/Applications/Bloom.app` and the `bloom`
link. Settings are in `~/Library/Preferences/io.github.astmirzhan.Bloom.plist`.

## Building

| Command | What it does |
|---|---|
| `make install-local` | Release build, signed for this Mac, installed to /Applications |
| `make run` | Builds a debug copy and opens it (needs [XcodeGen](https://github.com/yonaskolb/XcodeGen)) |
| `make test` | Runs all tests: the conversion engine's and the app's |
| `make core-test` | Runs only the conversion engine's tests |
| `make cli` | Builds the `bloom` command and prints its path |
| `make clean` | Removes the build output |

Builds go to `~/Library/Caches/Converter` rather than the project folder, because iCloud
Drive's file attributes break code signing.

## Project layout

- `Packages/ConverterCore`: the conversion engine (a Swift package with no UI), the `bloom` command and its tests.
- `Converter/App`: the menu bar app in SwiftUI and AppKit: the wheel, menus, job queue, settings, crop editor, metadata window, welcome window and file actions.
- `Converter/QuickAction`: the Finder Quick Action extension.
- `Converter/AppTests`: the app's tests.
- `docs/dev/design.md`: design notes.

## Contributing

Bug reports, format requests and pull requests are welcome; see [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT; see [LICENSE](LICENSE).
