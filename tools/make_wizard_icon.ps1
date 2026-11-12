# Builds art/wizard/icon.png (menu logo): the gnome with its wand, and a fireball and
# an iceball swooping in at it, on a transparent background like the other level icons.
# Uses the exported frames, so re-run after kra_export.ps1.
Add-Type -AssemblyName System.Drawing
$art = Join-Path $PSScriptRoot '..\art\wizard'
$N = 1024                                   # drawn big, saved at 256
$crop = @{ x = 0; y = 1320; size = 1120 }    # Krita canvas square shown in the icon
$f = $N / $crop.size
$bmp = New-Object Drawing.Bitmap $N, $N, ([Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g = [Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = 'AntiAlias'; $g.InterpolationMode = 'HighQualityBicubic'; $g.PixelOffsetMode = 'HighQuality'

# Krita layers in their canvas positions, back to front
function Layer($file, $cx, $cy) {
  $im = [Drawing.Image]::FromFile((Join-Path $art $file))
  $g.DrawImage($im, [single](($cx - $crop.x) * $f), [single](($cy - $crop.y) * $f), [single]($im.Width * 2 * $f), [single]($im.Height * 2 * $f))
  $im.Dispose()
}
# an incoming comet, its head (BALL_HEAD in the game, canvas px inside the drawing)
# placed at icon px (hx, hy) and drawn at the given share of its canvas size
function Comet($file, $hx, $hy, $scale) {
  $im = [Drawing.Image]::FromFile((Join-Path $art $file))
  $k = $f * $scale
  $g.DrawImage($im, [single]($hx - 115 * $k), [single]($hy - 765 * $k), [single]($im.Width * 2 * $k), [single]($im.Height * 2 * $k))
  $im.Dispose()
}
# two balls swooping in from the top right: the iceball further back, the fireball closer
Comet 'iceball_0.png' 800 170 0.2
Comet 'fireball_0.png' 560 330 0.28
Layer 'gnome_0.png' 0 1772
Layer 'wand.png' 452 1775
Layer 'gnome_hands.png' 609 2115

$out = New-Object Drawing.Bitmap 256, 256, ([Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g2 = [Drawing.Graphics]::FromImage($out); $g2.InterpolationMode = 'HighQualityBicubic'; $g2.PixelOffsetMode = 'HighQuality'
$g2.CompositingMode = 'SourceCopy'
$g2.DrawImage($bmp, 0, 0, 256, 256)
$out.Save((Join-Path $art 'icon.png'), [Drawing.Imaging.ImageFormat]::Png)
"saved icon.png"
