# Third-party components

John Walker's own code is in the public domain, and the packaging in this
repository is released under CC0 (see [LICENSE](LICENSE)). The following
bundled files were written by others and keep their own licenses.

| File | Author | License |
|---|---|---|
| `HDiet/Cgi/CGI.pm` | Lincoln D. Stein | May be used and modified freely; the copyright notice must stay attached, and a redistributed modified version must list its modifications. This copy is unmodified. |
| `HDiet/Text/CSV.pm` | Alan Citterman | Same terms as Perl itself (Artistic License or GPL) |
| `HDiet/Digest/Crc32.pm` | Faycal Chraibi | Same terms as Perl itself (Artistic License or GPL) |
| `HDiet/Util/IDNA/Punycode.pm` | Tatsuhiko Miyagawa, Robert Urban | CPAN module IDNA::Punycode, same terms as Perl itself |
| `wz_jsgraphics.js` | Walter Zorn | GNU LGPL 2.1 or later |
| `HDiet/Fonts/DejaVuLGCSans.ttf`, `HDiet/Fonts/DejaVuLGCSans-Bold.ttf` | Bitstream, Inc.; DejaVu fonts team | Bitstream Vera Fonts license with DejaVu changes (free to use, modify and redistribute) |

## Images in `figures/`

The logos, month navigation arrows, favicon, warning-stripe background and
sample badge were not part of the source distribution. They were copied
unchanged from <https://www.fourmilab.ch/hackdiet/online/figures/>, where
the running application uses them. Walker states explicitly that the source
code is in the public domain; these images belong to the same application
and are assumed to be in the public domain as well, but there is no
separate statement for them.

## Fonts installed in the image

| Font | Source | License |
|---|---|---|
| Liberation Serif | Debian package `fonts-liberation2` | SIL Open Font License 1.1 |

The original distribution included `HDiet/Fonts/Times.ttf`, Monotype's Times
New Roman as shipped with Microsoft Windows. It may not be redistributed, so
it has been removed. The container links the metric-compatible Liberation
Serif under the same file name, which is what the chart labels use.
