using System;
using System.Runtime.InteropServices;
public static class GenshinSubtitleOverlayNative {
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int key);
    [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr hWnd, int msg, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(System.Drawing.Point point);
    [DllImport("user32.dll")] static extern int GetWindowLong(IntPtr hWnd, int index);
    [DllImport("user32.dll")] static extern int SetWindowLong(IntPtr hWnd, int index, int value);
    public static void MakeNoActivate(IntPtr hWnd) {
        int style = GetWindowLong(hWnd, -20);
        SetWindowLong(hWnd, -20, style | 0x20 | 0x08000000);
    }
}
public class GenshinSubtitleToolbarForm : System.Windows.Forms.Form {
    public bool Collapsed { get; set; }
    public bool IsDragging { get; private set; }
    public System.Drawing.Rectangle MovementBounds { get; set; }
    public event EventHandler DragCompleted;
    public event EventHandler RestoreRequested;
    private System.Drawing.Point start, original;
    private bool moved;
    public GenshinSubtitleToolbarForm() { DoubleBuffered = true; }
    protected override bool ShowWithoutActivation { get { return true; } }
    protected override void OnMouseDown(System.Windows.Forms.MouseEventArgs e) {
        base.OnMouseDown(e);
        if (e.Button != System.Windows.Forms.MouseButtons.Left) return;
        start = PointToScreen(e.Location); original = Location;
        moved = false; IsDragging = true; Capture = true;
    }
    protected override void OnMouseMove(System.Windows.Forms.MouseEventArgs e) {
        base.OnMouseMove(e);
        Cursor = System.Windows.Forms.Cursors.SizeAll;
        if (!IsDragging) return;
        var p = PointToScreen(e.Location);
        int dx = p.X - start.X, dy = p.Y - start.Y;
        if (Math.Abs(dx) > 4 || Math.Abs(dy) > 4) moved = true;
        if (!moved) return;
        var bounds = MovementBounds;
        Location = new System.Drawing.Point(
            Math.Max(bounds.Left, Math.Min(bounds.Right - Width, original.X + dx)),
            Math.Max(bounds.Top, Math.Min(bounds.Bottom - Height, original.Y + dy)));
    }
    protected override void OnMouseUp(System.Windows.Forms.MouseEventArgs e) {
        base.OnMouseUp(e);
        if (e.Button != System.Windows.Forms.MouseButtons.Left || !IsDragging) return;
        IsDragging = false; Capture = false;
        if (moved) { if (DragCompleted != null) DragCompleted(this, EventArgs.Empty); }
        else if (Collapsed && RestoreRequested != null) RestoreRequested(this, EventArgs.Empty);
    }
    protected override void OnMouseCaptureChanged(EventArgs e) {
        base.OnMouseCaptureChanged(e);
        if (!Capture && IsDragging) {
            IsDragging = false;
            if (moved && DragCompleted != null) DragCompleted(this, EventArgs.Empty);
        }
    }
    protected override void OnPaint(System.Windows.Forms.PaintEventArgs e) {
        base.OnPaint(e);
        if (Collapsed) {
            using (var font = new System.Drawing.Font("Segoe MDL2 Assets", 18)) {
                System.Windows.Forms.TextRenderer.DrawText(e.Graphics, "\uE8F2", font, ClientRectangle,
                    System.Drawing.Color.FromArgb(30, 70, 90),
                    System.Windows.Forms.TextFormatFlags.HorizontalCenter | System.Windows.Forms.TextFormatFlags.VerticalCenter);
            }
        } else {
            for (int y = 12; y <= 28; y += 8)
                for (int x = 7; x <= 13; x += 6)
                    e.Graphics.FillRectangle(System.Drawing.Brushes.Gray, x, y, 2, 2);
        }
    }
}
public class GenshinSubtitleClickThroughForm : System.Windows.Forms.Form {
    public bool ClickThrough { get; set; }
    public GenshinSubtitleClickThroughForm() { ClickThrough = true; }
    protected override bool ShowWithoutActivation { get { return true; } }
    protected override void WndProc(ref System.Windows.Forms.Message message) {
        if (message.Msg == 0x84 && ClickThrough) { message.Result = new IntPtr(-1); return; }
        base.WndProc(ref message);
        if (message.Msg == 0x84 && !ClickThrough && message.Result == new IntPtr(1)) {
            message.Result = new IntPtr(2);
        }
    }
}
public class GenshinSubtitleCropForm : GenshinSubtitleSelectionForm {
    public GenshinSubtitleCropForm() {
        BackColor = System.Drawing.Color.FromArgb(130, 110, 25);
        SelectionColor = System.Drawing.Color.FromArgb(255, 225, 50);
    }
}
public class GenshinSubtitleSelectionForm : System.Windows.Forms.Form {
    public System.Drawing.Color SelectionColor { get; set; }
    public event EventHandler BoundsEdited;
    public event EventHandler EditCompleted;
    public System.Drawing.Rectangle MovementBounds { get; set; }
    public bool IsDragging { get; private set; }
    private int edges;
    private System.Drawing.Point start;
    private System.Drawing.Rectangle original;
    public GenshinSubtitleSelectionForm() {
        FormBorderStyle = System.Windows.Forms.FormBorderStyle.None;
        StartPosition = System.Windows.Forms.FormStartPosition.Manual;
        ShowInTaskbar = false; TopMost = true;
        BackColor = System.Drawing.Color.FromArgb(25, 90, 130);
        Opacity = 0.45;
        SelectionColor = System.Drawing.Color.White;
        DoubleBuffered = true;
        SetStyle(System.Windows.Forms.ControlStyles.ResizeRedraw, true);
    }
    protected override bool ShowWithoutActivation { get { return true; } }
    private int HitEdges(System.Drawing.Point p) {
        return (p.X < 12 ? 1 : p.X >= Width - 12 ? 2 : 0) |
               (p.Y < 12 ? 4 : p.Y >= Height - 12 ? 8 : 0);
    }
    protected override void OnMouseDown(System.Windows.Forms.MouseEventArgs e) {
        base.OnMouseDown(e);
        if (e.Button != System.Windows.Forms.MouseButtons.Left) return;
        edges = HitEdges(e.Location); start = PointToScreen(e.Location); original = Bounds;
        IsDragging = true; Capture = true;
    }
    protected override void OnMouseMove(System.Windows.Forms.MouseEventArgs e) {
        base.OnMouseMove(e);
        int hit = IsDragging ? edges : HitEdges(e.Location);
        Cursor = hit == 5 || hit == 10 ? System.Windows.Forms.Cursors.SizeNWSE :
                 hit == 6 || hit == 9 ? System.Windows.Forms.Cursors.SizeNESW :
                 (hit & 3) != 0 ? System.Windows.Forms.Cursors.SizeWE :
                 (hit & 12) != 0 ? System.Windows.Forms.Cursors.SizeNS : System.Windows.Forms.Cursors.SizeAll;
        if (!IsDragging) return;
        var point = PointToScreen(e.Location);
        int dx = point.X - start.X, dy = point.Y - start.Y;
        var limit = MovementBounds;
        int l = original.Left, t = original.Top, r = original.Right, b = original.Bottom;
        int minW = Math.Min(Math.Max(128, (int)Math.Ceiling(limit.Width * 0.05)), limit.Width);
        int minH = Math.Min(Math.Max(64, (int)Math.Ceiling(limit.Height * 0.05)), limit.Height);
        if (edges == 0) {
            l = Math.Max(limit.Left, Math.Min(limit.Right - original.Width, l + dx));
            t = Math.Max(limit.Top, Math.Min(limit.Bottom - original.Height, t + dy));
            r = l + original.Width; b = t + original.Height;
        } else {
            if ((edges & 1) != 0) l = Math.Max(limit.Left, Math.Min(r - minW, l + dx));
            if ((edges & 2) != 0) r = Math.Min(limit.Right, Math.Max(l + minW, r + dx));
            if ((edges & 4) != 0) t = Math.Max(limit.Top, Math.Min(b - minH, t + dy));
            if ((edges & 8) != 0) b = Math.Min(limit.Bottom, Math.Max(t + minH, b + dy));
        }
        Bounds = System.Drawing.Rectangle.FromLTRB(l, t, r, b);
        if (BoundsEdited != null) BoundsEdited(this, EventArgs.Empty);
    }
    private void EndEdit() {
        if (!IsDragging) return;
        IsDragging = false; Capture = false;
        if (EditCompleted != null) EditCompleted(this, EventArgs.Empty);
    }
    protected override void OnMouseUp(System.Windows.Forms.MouseEventArgs e) {
        base.OnMouseUp(e);
        if (e.Button == System.Windows.Forms.MouseButtons.Left) EndEdit();
    }
    protected override void OnMouseCaptureChanged(EventArgs e) {
        base.OnMouseCaptureChanged(e);
        if (!Capture) EndEdit();
    }
    protected override void OnPaint(System.Windows.Forms.PaintEventArgs e) {
        base.OnPaint(e);
        using (var pen = new System.Drawing.Pen(SelectionColor, 2)) {
            e.Graphics.DrawRectangle(pen, 1, 1, Width - 3, Height - 3);
        }
        foreach (int x in new int[] { 1, Width / 2 - 4, Width - 9 })
            foreach (int y in new int[] { 1, Height / 2 - 4, Height - 9 })
                if (x != Width / 2 - 4 || y != Height / 2 - 4)
                    using (var brush = new System.Drawing.SolidBrush(SelectionColor))
                        e.Graphics.FillRectangle(brush, x, y, 8, 8);
    }
}
