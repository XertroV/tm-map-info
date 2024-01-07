// an obscure characture, used by nvg text to avoid mis-rendering spaces. should be about the size of a space.
const string SPACE_CHAR = "|";
const float TAU = 6.28318530717958647692;

/**
 * Parse a color string and provide a draw function so that we can draw colored text.
 *
 * Sometimes skips spaces. examples:
 * 'once in a blue moon' 2022-10-04
 * 'maobikzy -desert' 2022-10-14
 * 'castello arcobaleno ft queen_clown' 2022-10-16
 */
class NvgText {
    string[]@ parts;
    vec3[] cols;

    NvgText(const string &in coloredText) {
        log_debug('NvgText orig: ' + coloredText);
        auto preText = MakeColorsOkayDarkMode(ColoredString((coloredText))).Replace(" ", SPACE_CHAR);
        // auto preText = ColoredString((coloredText)).Replace(" ", SPACE_CHAR);
        @parts = preText.Split("\\$");
        uint startAt = 0;
        if (!preText.StartsWith("\\$")) {
            startAt = 1;
            cols.InsertLast(vec3(-1, -1, -1));
        }
        for (uint i = startAt; i < parts.Length; i++) {
            if (parts[i].Length == 0) {
                cols.InsertLast(i == 0 ? vec3(-1, -1, -1) : cols[cols.Length - 1]);
                continue;
            }
            string firstChar = parts[i].SubStr(0, 1).ToLower();
            if (firstChar[0] == zChar || firstChar[0] == gChar) {
                parts[i] = parts[i].SubStr(1);
                cols.InsertLast(vec3(-1, -1, -1));
                continue;
            } else if (IsASkipChar(firstChar[0]) || parts[i].Length == 1) {
                parts[i] = parts[i].SubStr(1);
                cols.InsertLast(i == 0 ? vec3(-1, -1, -1) : cols[cols.Length - 1]);
                continue;
            } else if (parts[i].Length < 4) {
                parts[i] = "";
                cols.InsertLast(i == 0 ? vec3(-1, -1, -1) : cols[cols.Length - 1]);
                continue;
            }

            auto hex = parts[i].SubStr(0, 3);
            parts[i] = parts[i].SubStr(3);
            // fix rendering of spaces at start of words -- move to prior word
            while (i > 0 && parts[i].SubStr(0, 1) == SPACE_CHAR) {
                parts[i - 1] += SPACE_CHAR;
                parts[i] = parts[i].SubStr(1);
            }
            cols.InsertLast(hexTriToRgb(hex));
        }
        // cache the string value
        ToString();
    }

    uint8 sChar = "s"[0];
    uint8 oChar = "o"[0];
    uint8 zChar = "z"[0];
    uint8 iChar = "i"[0];
    uint8 gChar = "g"[0];
    uint8 ltChar = "<"[0];
    uint8 gtChar = ">"[0];

    bool IsASkipChar(uint8 char) {
        //  || char == gChar
        return char == oChar || char == iChar || char == sChar || char == ltChar || char == gtChar;
    }

    float strokeIters = 9;
    void Draw(vec2 pos, vec3 defaultCol, float fs, float alpha, float strokeSize) {
        // if (strokeSize < 0) strokeSize = fs * 0.1;
        // for (float i = 0; i < 1; i += 1. / strokeIters) {
        //     float theta = TAU * i;
        //     Draw(pos + vec2(Math::Sin(theta), Math::Cos(theta)) * strokeSize, vec3(0, 0, 0), fs, alpha, true);
        // }
        Draw(pos, defaultCol, fs, alpha);
    }

    void Draw(vec2 pos, vec3 defaultCol, float fs, float alpha = 1.0, bool suppressColor = false) {
        float xOff = 0;
        for (uint i = 0; i < parts.Length; i++) {
            auto col = cols[i];
            if (suppressColor || col.x < 0) col = defaultCol;
            nvg::FillColor(vec4(col.x, col.y, col.z, alpha));
            auto xy = nvg::TextBounds(parts[i]);
            nvg::Text(pos + vec2(xOff, 0), parts[i].Replace(SPACE_CHAR, " "));
            // nvg::Text(pos + vec2(xOff, 0), parts[i]);
            xOff += Math::Max(0.0, xy.x - fs / 7.0);
        }
        nvg::FillColor(vec4(defaultCol.x, defaultCol.y, defaultCol.z, alpha));
    }

    string _asStr;
    const string ToString() {
        if (_asStr.Length == 0) {
            for (uint i = 0; i < parts.Length; i++) {
                // auto item = parts[i];
                _asStr += "$" + rgbToHexTri(cols[i].x < 0 ? vec3(1,1,1) : cols[i]);
                _asStr += parts[i];
            }
            _asStr = _asStr.Replace(SPACE_CHAR, " ");
        }
        return _asStr;
    }
}


bool IsCharInt(int char) {
    return 48 <= char && char <= 57;
}

bool IsCharInAToF(int char) {
    return (97 <= char && char <= 102) /* lower case */
        || (65 <= char && char <= 70); /* upper case */
}

bool IsCharHex(int char) {
    return IsCharInt(char) || IsCharInAToF(char);
}

uint8 HexCharToInt(int char) {
    if (IsCharInt(char)) {
        return char - 48;
    }
    if (IsCharInAToF(char)) {
        int v = char - 65 + 10;  // A = 65 ascii
        if (v < 16) return v;
        return v - (97 - 65);    // a = 97 ascii
    }
    log_warn("HexCharToInt got char with code " + char + " but that isn't 0-9 or a-f or A-F in ascii.");
    return 15;
}

vec3 hexTriToRgb(const string &in hexTri) {
    if (hexTri.Length != 3) { throw ("hextri must have 3 characters. bad input: " + hexTri); }
    try {
        float r = HexCharToInt(hexTri[0]);
        float g = HexCharToInt(hexTri[1]);
        float b = HexCharToInt(hexTri[2]);
        return vec3(r, g, b) / 15.;
    } catch {
        throw("Exception while processing hexTri (" + hexTri + "): " + getExceptionInfo());
    }
    return vec3();
}



enum ColorTy {
    RGB,
    // LAB,
    // XYZ,
    HSL,
}



const uint asciiDollarSign = "$"[0];



dictionary@ DARK_MODE_CACHE = dictionary();

const string MakeColorsOkayDarkMode(const string &in raw) {
    /* - find color values
       - for each color value:
         - luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
         - luma < .4 { replace color }
       return;
    */
    // we need at least 4 chars to test $123, so only go to length-3 to test for $.
    if (DARK_MODE_CACHE.Exists(raw)) {
        return string(DARK_MODE_CACHE[raw]);
    }
    string ret = string(raw);
    string _test;
    for (int i = 0; i < int(ret.Length) - 3; i++) {
        if (ret[i] == asciiDollarSign) {
            _test = ret.SubStr(i, 4);
            if (IsCharHex(_test[1]) && IsCharHex(_test[2]) && IsCharHex(_test[3])) {
                auto c = Color(vec3(
                    float(HexCharToInt(_test[1])) / 15.,
                    float(HexCharToInt(_test[2])) / 15.,
                    float(HexCharToInt(_test[3])) / 15.
                ));
                c.AsHSL();
                float l = c.v.z;  /* lightness part of HSL */
                if (l < 60) {
                    // logcall("MakeColorsOkayDarkMode", "fixing color: " + _test + " / " + c.ManiaColor + " / " + c.ToString());
                    c.v = vec3(c.v.x, c.v.y, Math::Max(100. - l, 60));
                    // logcall("MakeColorsOkayDarkMode", "new color: " + Vec3ToStr(c.get_rgb()) + " / " + c.ManiaColor + " / " + c.ToString());
                    ret = ret.Replace(_test, c.ManiaColor);
                }
            }
        }
    }
    DARK_MODE_CACHE[raw] = ret;
    return ret;
}


vec3 rgbToHSL(vec3 rgb) {
    float r = rgb.x;
    float g = rgb.y;
    float b = rgb.z;
    float max = Math::Max(r, Math::Max(g, b));
    float min = Math::Min(r, Math::Min(g, b));
    float h, s, l;
    l = (max + min) / 2.;
    if (max == min) {
        h = s = 0;
    } else {
        float d = max - min;
        s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
        h = max == r
            ? (g-b) / d + (g < b ? 6 : 0)
            : max == g
                ? (b - r) / d + 2
                /* it must be that: max == b */
                : (r - g) / d + 4;
        h /= 6;
    }
    return vec3(
        Math::Clamp(h * 360., 0., 360.),
        Math::Clamp(s * 100., 0., 100.),
        Math::Clamp(l * 100., 0., 100.));
}


uint8 ToSingleHexCol(float v) {
    if (v < 0) { v = 0; }
    if (v > 15.9999) { v = 15.9999; }
    int u = uint8(Math::Floor(v));
    if (u < 10) { return 48 + u; }  /* 48 = '0' */
    return 87 + u;  /* u>=10 and 97 = 'a' */
}

string rgbToHexTri(vec3 rgb) {
    auto v = rgb * 15;
    string ret = "000";
    ret[0] = ToSingleHexCol(v.x);
    ret[1] = ToSingleHexCol(v.y);
    ret[2] = ToSingleHexCol(v.z);
    return ret;
}


float h2RGB(float p, float q, float t) {
    if (t < 0) { t += 1; }
    if (t > 1) { t -= 1; }
    if (t < 0.16667) { return p + (q-p) * 6. * t; }
    if (t < 0.5) { return q; }
    if (t < 0.66667) { return p + (q-p) * 6. * (2./3. - t); }
    return p;
}

vec3 hslToRGB(vec3 hsl) {
    float h = hsl.x / 360.;
    float s = hsl.y / 100.;
    float l = hsl.z / 100.;
    float r, g, b, p, q;
    if (s == 0) {
        r = g = b = l;
    } else {
        q = l < 0.5 ? (l + l*s) : (l + s - l*s);
        p = 2.*l - q;
        r = h2RGB(p, q, h + 1./3.);
        g = h2RGB(p, q, h);
        b = h2RGB(p, q, h - 1./3.);
    }
    return vec3(r, g, b);
}



class Color {
    ColorTy ty;
    vec3 v;

    Color(vec3 _v, ColorTy _ty = ColorTy::RGB) {
        v = _v; ty = _ty;
    }

    string ToString() {
        return "Color(" + v.ToString() + ", " + tostring(ty) + ")";
    }

    // vec4 rgba(float a) {
    //     auto _v = this.rgb;
    //     return vec4(_v.x, _v.y, _v.z, a);
    // }

    string get_ManiaColor() {
        return "$" + this.HexTri;
    }

    string get_HexTri() {
        return rgbToHexTri(this.rgb);
    }

    // void AsLAB() {
    //     if (ty == ColorTy::LAB) { return; }
    //     if (ty == ColorTy::XYZ) { v = xyzToLAB(v); }
    //     if (ty == ColorTy::RGB) { v = xyzToLAB(rgbToXYZ(v)); }
    //     if (ty == ColorTy::HSL) { v = xyzToLAB(rgbToXYZ(hslToRGB(v))); }
    //     ty = ColorTy::LAB;
    // }

    void AsRGB() {
        if (ty == ColorTy::RGB) { return; }
        // if (ty == ColorTy::XYZ) { v = xyzToRGB(v); }
        // if (ty == ColorTy::LAB) { v = xyzToRGB(labToXYZ(v)); }
        if (ty == ColorTy::HSL) { v = hslToRGB(v); }
        ty = ColorTy::RGB;
    }

    void AsHSL() {
        if (ty == ColorTy::HSL) { return; }
        if (ty == ColorTy::RGB) { v = rgbToHSL(v); }
        // if (ty == ColorTy::XYZ) { v = rgbToHSL(xyzToRGB(v)); }
        // if (ty == ColorTy::LAB) { v = rgbToHSL(xyzToRGB(labToXYZ(v))); }
        ty = ColorTy::HSL;
    }

    // void AsXYZ() {
    //     if (ty == ColorTy::XYZ) { return; }
    //     if (ty == ColorTy::RGB) { v = rgbToXYZ(v); }
    //     if (ty == ColorTy::LAB) { v = labToXYZ(v); }
    //     if (ty == ColorTy::HSL) { v = rgbToXYZ(hslToRGB(v)); }
    //     ty = ColorTy::XYZ;
    // }

    // Color@ ToLAB() {
    //     auto ret = Color(v, this.ty);
    //     ret.AsLAB();
    //     return ret;
    // }

    // Color@ ToXYZ() {
    //     auto ret = Color(v, this.ty);
    //     ret.AsXYZ();
    //     return ret;
    // }

    Color@ ToRGB() {
        auto ret = Color(v, this.ty);
        ret.AsRGB();
        return ret;
    }

    Color@ ToHSL() {
        auto ret = Color(v, this.ty);
        ret.AsHSL();
        return ret;
    }

    // Color@ ToMode(ColorTy mode) {
    //     switch (mode) {
    //         case ColorTy::RGB: return ToRGB();
    //         case ColorTy::XYZ: return ToXYZ();
    //         case ColorTy::LAB: return ToLAB();
    //         case ColorTy::HSL: return ToHSL();
    //     }
    //     throw("Unknown ColorTy mode: " + mode);
    //     return ToRGB();
    // }

    vec3 get_rgb() {
        if (ty == ColorTy::RGB) { return vec3(v); }
        // if (ty == ColorTy::XYZ) { return xyzToRGB(v); }
        // if (ty == ColorTy::LAB) { return xyzToRGB(labToXYZ(v)); }
        if (ty == ColorTy::HSL) { return hslToRGB(v); }
        throw("Unknown color type: " + ty);
        return vec3();
    }

    // vec3 get_lab() {
    //     if (ty == ColorTy::LAB) { return vec3(v); }
    //     if (ty == ColorTy::XYZ) { return xyzToLAB(v); }
    //     if (ty == ColorTy::RGB) { return xyzToLAB(rgbToXYZ(v)); }
    //     if (ty == ColorTy::HSL) { return xyzToLAB(rgbToXYZ(hslToRGB(v))); }
    //     throw("Unknown color type: " + ty);
    //     return vec3();
    // }
}
