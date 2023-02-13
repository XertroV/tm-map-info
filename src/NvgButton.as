// augmentation for behavior in MapInfo_UI
class NvgButton {
    CoroutineFunc@ onClick = null;
    AnimMgr@ anim = AnimMgr(false, 100.0);
    vec4 col;
    vec4 textHoverCol;

    NvgButton(vec4 bgColor, vec4 textHoverCol, CoroutineFunc@ onClick) {
        this.col = bgColor;
        this.textHoverCol = textHoverCol;
        @this.onClick = onClick;
    }

    vec2 lastTL = vec2(-1, -1);
    vec2 lastSize = vec2(-1, -1);

    void DrawButton(vec2 textPos, vec2 textSize, vec4 textCol, vec2 padding, float clampMax, float xScale) {
        vec2 tl = textPos - padding;
        vec2 size = textSize + padding * 2.0;
        bool growing = IsWithin(g_MouseCoords, tl * vec2(xScale, 1), size * vec2(xScale, 1));

        if (!anim.Update(growing, clampMax)) return;
        float alpha = anim.Progress;
        lastTL = tl; lastSize = size;

        nvg::BeginPath();
        nvg::Rect(tl, size);
        nvg::FillColor(col * vec4(1, 1, 1, alpha));
        nvg::Fill();
        nvg::ClosePath();
        nvg::FillColor(textHoverCol * alpha + textCol * (1.0 - alpha));
    }

    bool OnMouseClick(bool down, int button) {
        if (down && button == 0 && anim.Progress > 0 && IsWithin(g_MouseCoords, lastTL, lastSize)) {
            onClick();
            return true;
        }
        return false;
    }
}
