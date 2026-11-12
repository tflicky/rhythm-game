param([string]$Kra, [string]$OutDir)
# Exports every animated paint layer of a Krita .kra as transparent PNG frames,
# applying each layer's HSV/HSL filter mask. Frames of one layer share a crop box
# so they stay aligned; boxes are written to frames.json (canvas coordinates).
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System; using System.IO; using System.Collections.Generic; using System.Drawing; using System.Drawing.Imaging;
public static class Kra {
  static byte[] Lzf(byte[] a, int start, int len, int outLen) {
    var o = new byte[outLen]; int ip = start, end = start + len, op = 0;
    while (ip < end) {
      int c = a[ip++];
      if (c < 32) { c++; Array.Copy(a, ip, o, op, c); ip += c; op += c; }
      else { int l = c >> 5; int r = op - ((c & 31) << 8) - 1; if (l == 7) l += a[ip++]; r -= a[ip++]; l += 2;
        for (int i = 0; i < l; i++) o[op++] = o[r++]; }
    }
    return o;
  }
  // returns BGRA canvas
  public static byte[] Decode(byte[] d, int W, int H, int dx, int dy) {
    var px = new byte[W * H * 4]; int p = 0;
    Func<string> line = () => { int s = p; while (d[p] != 10) p++; string t = System.Text.Encoding.ASCII.GetString(d, s, p - s); p++; return t; };
    line(); int tw = int.Parse(line().Split(' ')[1]); int th = int.Parse(line().Split(' ')[1]); line();
    int n = int.Parse(line().Split(' ')[1]);
    for (int t = 0; t < n; t++) {
      var f = line().Split(','); int tx = int.Parse(f[0]), ty = int.Parse(f[1]), sz = int.Parse(f[3]);
      int plane = tw * th; byte[] raw;
      if (d[p] == 1) raw = Lzf(d, p + 1, sz - 1, plane * 4); else { raw = new byte[plane * 4]; Array.Copy(d, p + 1, raw, 0, plane * 4); }
      p += sz;
      for (int y = 0; y < th; y++) { int cy = ty + y + dy; if (cy < 0 || cy >= H) continue;
        for (int x = 0; x < tw; x++) { int cx = tx + x + dx; if (cx < 0 || cx >= W) continue;
          int i = y * tw + x, o = (cy * W + cx) * 4;
          for (int ch = 0; ch < 4; ch++) px[o + ch] = raw[ch * plane + i]; } }
    }
    return px;
  }
  public static void Hsl(byte[] px, double h, double s, double v) {
    for (int o = 0; o < px.Length; o += 4) {
      if (px[o + 3] == 0) continue;
      double b = px[o] / 255.0, g = px[o + 1] / 255.0, r = px[o + 2] / 255.0;
      double mx = Math.Max(r, Math.Max(g, b)), mn = Math.Min(r, Math.Min(g, b)), L = (mx + mn) / 2, S = 0, Hh = 0, dd = mx - mn;
      if (dd > 1e-9) { S = L > 0.5 ? dd / (2 - mx - mn) : dd / (mx + mn);
        if (mx == r) Hh = (g - b) / dd + (g < b ? 6 : 0); else if (mx == g) Hh = (b - r) / dd + 2; else Hh = (r - g) / dd + 4; Hh *= 60; }
      Hh = (Hh + h) % 360; if (Hh < 0) Hh += 360;
      S = s >= 0 ? S + (1 - S) * s : S * (1 + s); L = v >= 0 ? L + (1 - L) * v : L * (1 + v);
      double q = L < 0.5 ? L * (1 + S) : L + S - L * S, pp = 2 * L - q, hk = Hh / 360;
      Func<double, double> f = t => { if (t < 0) t += 1; if (t > 1) t -= 1; if (t < 1.0/6) return pp + (q - pp) * 6 * t; if (t < 0.5) return q; if (t < 2.0/3) return pp + (q - pp) * (2.0/3 - t) * 6; return pp; };
      px[o + 2] = (byte)Math.Round(255 * f(hk + 1.0/3)); px[o + 1] = (byte)Math.Round(255 * f(hk)); px[o] = (byte)Math.Round(255 * f(hk - 1.0/3));
    }
  }
  public static int[] Bounds(byte[] px, int W, int H) {
    int x0 = W, y0 = H, x1 = -1, y1 = -1;
    for (int y = 0; y < H; y++) for (int x = 0; x < W; x++) if (px[(y * W + x) * 4 + 3] > 8) { if (x < x0) x0 = x; if (x > x1) x1 = x; if (y < y0) y0 = y; if (y > y1) y1 = y; }
    return new int[] { x0, y0, x1, y1 };
  }
  public static void Save(byte[] px, int W, int[] box, string path) {
    int w = box[2] - box[0] + 1, h = box[3] - box[1] + 1;
    using (var bmp = new Bitmap(w, h, PixelFormat.Format32bppArgb)) {
      var bd = bmp.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
      var row = new byte[w * 4];
      for (int y = 0; y < h; y++) { Array.Copy(px, ((box[1] + y) * W + box[0]) * 4, row, 0, w * 4);
        System.Runtime.InteropServices.Marshal.Copy(row, 0, bd.Scan0 + y * bd.Stride, w * 4); }
      bmp.UnlockBits(bd);
      // saved at half size (the game draws them at TEX_SCALE 2)
      int hw = Math.Max(1, (w + 1) / 2), hh = Math.Max(1, (h + 1) / 2);
      using (var half = new Bitmap(hw, hh, PixelFormat.Format32bppArgb))
      using (var g = Graphics.FromImage(half)) {
        g.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.HighQualityBicubic;
        g.PixelOffsetMode = System.Drawing.Drawing2D.PixelOffsetMode.HighQuality;
        g.CompositingMode = System.Drawing.Drawing2D.CompositingMode.SourceCopy;
        using (var ia = new ImageAttributes()) {
          ia.SetWrapMode(System.Drawing.Drawing2D.WrapMode.TileFlipXY);
          g.DrawImage(bmp, new Rectangle(0, 0, w / 2, h / 2), 0, 0, w, h, GraphicsUnit.Pixel, ia);
        }
        half.Save(path, ImageFormat.Png);
      }
    }
  }
}
'@

$z = [IO.Compression.ZipFile]::OpenRead($Kra)
function ReadEntry($name) { $e = $z.GetEntry($name); $ms = New-Object IO.MemoryStream; $s = $e.Open(); $s.CopyTo($ms); $s.Close(); return ,$ms.ToArray() }
function ReadText($name) { return [Text.Encoding]::UTF8.GetString((ReadEntry $name)) }
$doc = [xml](ReadText 'maindoc.xml')
$img = $doc.DOC.IMAGE
$W = [int]$img.width; $H = [int]$img.height; $base = $img.name
New-Item -ItemType Directory -Force $OutDir | Out-Null
$meta = @{ canvas = @($W, $H); layers = @{} }
foreach ($L in $img.layers.layer) {
  if ($L.nodetype -ne 'paintlayer' -or $L.name -eq 'Background') { continue }
  $name = ($L.name -replace '\d+$','').Trim() -replace ' ','_'   # fireball2 -> fireball, gnome hands -> gnome_hands
  $hsl = $null
  if ($L.masks) { foreach ($m in $L.masks.mask) { if ($m.filtername -eq 'hsvadjustment' -and $m.visible -eq '1') {
    $cfg = [xml](ReadText "$base/layers/$($m.filename).filterconfig"); $p = @{}
    foreach ($q in $cfg.params.param) { $p[$q.name] = $q.InnerText }; $hsl = $p } } }
  $frames = @()
  if ($L.keyframes) {
    $kx = [xml](ReadText "$base/layers/$($L.keyframes)")
    $frames = @($kx.keyframes.channel.keyframe | Sort-Object { [int]$_.time } | ForEach-Object { ,@($_.frame, [int]$_.offset.x, [int]$_.offset.y) })
  } else { $frames = @(,@($L.filename, [int]$L.x, [int]$L.y)) }
  $decoded = @(); $box = @($W, $H, -1, -1)
  foreach ($f in $frames) {
    $px = [Kra]::Decode((ReadEntry "$base/layers/$($f[0])"), $W, $H, $f[1], $f[2])
    if ($hsl) { [Kra]::Hsl($px, [double]$hsl.h, [double]$hsl.s / 100.0, [double]$hsl.v / 100.0) }
    $b = [Kra]::Bounds($px, $W, $H)
    if ($b[2] -ge 0) { $box = @([Math]::Min($box[0],$b[0]), [Math]::Min($box[1],$b[1]), [Math]::Max($box[2],$b[2]), [Math]::Max($box[3],$b[3])) }
    $decoded += ,$px
  }
  if ($box[2] -lt 0) { "skip empty $name"; continue }
  $files = @()
  for ($i = 0; $i -lt $decoded.Count; $i++) {
    $fn = if ($decoded.Count -eq 1) { "$name.png" } else { "${name}_$i.png" }
    [Kra]::Save($decoded[$i], $W, $box, (Join-Path $OutDir $fn)); $files += $fn
  }
  $meta.layers[$name] = @{ box = $box; files = $files }
  "{0}: {1} frames, box {2}" -f $name, $files.Count, ($box -join ',')
}
$z.Dispose()
$meta | ConvertTo-Json -Depth 5 | Set-Content -Encoding utf8 (Join-Path $OutDir 'frames.json')
