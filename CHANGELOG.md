# Changelog

## 1.0.0 (unreleased)

The first Bloom release.

- **Petals style for the wheel**, now the default: a compact clear-glass disc with eight
  separate Liquid Glass petals, file extensions as labels (JPG, PDF, DOCX), an icon over a
  short caption on the Tools and Actions rings, a centre capsule that names what a drop will
  do (or the file's size), and a sky-blue highlight. Settings offer burgundy or orange
  instead, and the Classic style.
- **Sound and haptic feedback** as the pointer reaches a slice: a trackpad tap plus a sound
  you choose in Settings (a soft built-in note, or Tink, Pop, Morse, Purr or Bottle).
- **Smoother dragging**: the wheel redraws only when the slice under the pointer changes,
  not on every pointer move.
- Builds with Xcode 26.
- `make install-local` builds, signs for this Mac and installs to /Applications.

Bloom is based on [Swivel](https://github.com/jonathanlotan/Swivel) 1.0.0 (MIT): the
conversion engine, the drag-and-tap wheel, the `bloom` command line and Shortcuts support.
