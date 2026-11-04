#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// Value noise + fBm, cheap enough for a full-window background at 30 fps.
static float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

static float valueNoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float a = hash21(i);
    float b = hash21(i + float2(1.0, 0.0));
    float c = hash21(i + float2(0.0, 1.0));
    float d = hash21(i + float2(1.0, 1.0));
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

static float fbm(float2 p) {
    float value = 0.0;
    float amplitude = 0.5;
    for (int i = 0; i < 4; i++) {
        value += amplitude * valueNoise(p);
        p *= 2.03;
        amplitude *= 0.5;
    }
    return value;
}

/// Topographic contour lines drifting slowly, tinted across the width.
[[ stitchable ]] half4 topographicFlow(float2 position, half4 color, float2 size, float time,
                                       half4 tintA, half4 tintB, float density) {
    float2 uv = position / max(size.y, 1.0);
    float n = fbm(uv * 2.2 + float2(time * 0.030, -time * 0.020))
            + 0.35 * fbm(uv * 4.0 - float2(time * 0.015, time * 0.010));
    float bands = n * density;
    float f = fract(bands);
    float edge = min(f, 1.0 - f);
    float lineWidth = density * 0.0035;
    float line = 1.0 - smoothstep(0.0, lineWidth, edge);
    float glow = 1.0 - smoothstep(0.0, lineWidth * 7.0, edge);
    float across = clamp(position.x / max(size.x, 1.0), 0.0, 1.0);
    half4 tint = mix(tintA, tintB, half(smoothstep(0.1, 0.9, across)));
    float alpha = line * 0.55 + glow * 0.08;
    return half4(tint.rgb * half(alpha), half(alpha));
}

// ============================================================================
// Driftwall Originals: live scenes rendered at native resolution.
// All scenes are original procedural artwork. Coordinates: uv in 0..1, y up.
// ============================================================================

/// smoothstep that also accepts edge0 > edge1 (Metal leaves that case undefined).
static float sstep(float edge0, float edge1, float x) {
    return edge0 < edge1 ? smoothstep(edge0, edge1, x) : 1.0 - smoothstep(edge1, edge0, x);
}

static float2 sceneUV(float2 position, float2 size) {
    return float2(position.x / max(size.x, 1.0), 1.0 - position.y / max(size.y, 1.0));
}






// ---------------------------------------------------------------------------
// Extra helpers for the art styles.
// ---------------------------------------------------------------------------

static float2 rotate2(float2 v, float a) { float c = cos(a), s = sin(a); return float2(c * v.x - s * v.y, s * v.x + c * v.y); }

static float paperGrain(float2 p) {
    return 0.55 * valueNoise(p * 420.0) + 0.3 * valueNoise(p * 90.0) + 0.15 * fbm(p * 7.0);
}

/// Distance to nearest and second-nearest Voronoi points, plus the nearest cell id.
static float3 voronoi(float2 p, float time, float drift) {
    float2 cell = floor(p);
    float2 local = fract(p);
    float d1 = 8.0, d2 = 8.0;
    float id = 0.0;
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            float2 g = float2(float(x), float(y));
            float2 h = float2(hash21(cell + g), hash21(cell + g + 17.3));
            float2 o = 0.5 + 0.42 * sin(time * drift + 6.2831 * h);
            float d = length(g + o - local);
            if (d < d1) { d2 = d1; d1 = d; id = hash21(cell + g + 3.7); } else if (d < d2) { d2 = d; }
        }
    }
    return float3(d1, d2, id);
}

static float bayer4(float2 pixel) {
    int x = int(fmod(pixel.x, 4.0)), y = int(fmod(pixel.y, 4.0));
    const float m[16] = { 0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5 };
    return (m[y * 4 + x] + 0.5) / 16.0;
}

static float halftone(float2 p, float density, float angle, float freq) {
    float2 q = rotate2(p, angle) * freq;
    float2 cell = fract(q) - 0.5;
    float radius = sqrt(clamp(density, 0.0, 1.0)) * 0.62;
    return sstep(radius + 0.04, radius - 0.04, length(cell));
}

// ---------------------------------------------------------------------------
// 1. Ink & Mist: sumi-e ink wash on rice paper.
// ---------------------------------------------------------------------------
[[ stitchable ]] half4 originalInkMist(float2 position, half4 color, float2 size, float time) {
    float2 uv = sceneUV(position, size);
    float aspect = size.x / max(size.y, 1.0);
    float2 p = float2(uv.x * aspect, uv.y);
    float3 paper = float3(0.95, 0.92, 0.85) * (0.93 + 0.07 * paperGrain(p)) - 0.04 * fbm(p * 3.0);
    float3 ink = float3(0.10, 0.11, 0.14);
    float3 col = paper;
    float sun = sstep(0.065, 0.06, length(p - float2(0.78 * aspect, 0.74)));
    col = mix(col, float3(0.86, 0.32, 0.24), sun * 0.75);
    for (int i = 0; i < 5; i++) {
        float fi = float(i);
        float drift = time * 0.004 * (fi + 1.0);
        float ridge = 0.66 - fi * 0.11
            + 0.16 * (fbm(float2((p.x + drift) * (0.9 + fi * 0.35) + fi * 3.7, fi * 1.3)) - 0.5)
            + 0.05 * sin((p.x + drift) * (1.4 + fi) + fi);
        float edgeNoise = 0.012 * (fbm(p * 30.0 + fi) - 0.5);
        if (uv.y < ridge + edgeNoise) {
            float depth = ridge - uv.y;
            float wash = exp(-depth * (7.0 - fi * 0.9)) * 0.9 + 0.1;
            float bleed = 0.8 + 0.4 * fbm(float2(p.x * 9.0, uv.y * 30.0) + fi * 5.0);
            float strength = clamp(wash * bleed * (0.22 + fi * 0.17), 0.0, 1.0);
            col = mix(col, ink, strength);
        }
        float mistY = ridge - 0.06;
        float mist = exp(-pow((uv.y - mistY) * 12.0, 2.0)) * sstep(0.35, 0.75, fbm(float2((p.x - time * 0.015 * (fi + 1.0)) * 1.6, fi * 2.0)));
        col = mix(col, paper, mist * 0.85);
    }
    for (int b = 0; b < 3; b++) {
        float fb = float(b);
        float2 c = float2(fract(0.1 + fb * 0.13 + time * 0.012) * (aspect + 0.4) - 0.2, 0.80 - fb * 0.035 + 0.01 * sin(time * 0.7 + fb));
        float2 d = (p - c) * float2(1.0, 1.0);
        float flap = 0.35 + 0.25 * sin(time * 3.0 + fb * 2.0);
        float wing = abs(d.y + abs(d.x) * flap) - 0.0015;
        float bird = sstep(0.0018, 0.0, wing) * step(abs(d.x), 0.018 - fb * 0.003);
        col = mix(col, ink, bird * 0.9);
    }
    float2 sealP = p - float2(0.93 * aspect, 0.12);
    float seal = step(abs(sealP.x), 0.022) * step(abs(sealP.y), 0.03);
    float carve = step(0.5, fract((sealP.x + sealP.y) * 60.0)) * step(abs(sealP.x), 0.014) * step(abs(sealP.y), 0.022);
    col = mix(col, float3(0.78, 0.15, 0.12), seal * (1.0 - carve * 0.6) * (0.85 + 0.15 * paperGrain(p * 2.0)));
    return half4(half3(col), 1.0);
}

// ---------------------------------------------------------------------------
// 2. Paper Valley: layered papercraft diorama with cast shadows.
// ---------------------------------------------------------------------------
[[ stitchable ]] half4 originalPaperValley(float2 position, half4 color, float2 size, float time) {
    float2 uv = sceneUV(position, size);
    float aspect = size.x / max(size.y, 1.0);
    float2 p = float2(uv.x * aspect, uv.y);
    float grain = 0.94 + 0.06 * paperGrain(p * 0.7);
    float3 col = mix(float3(1.0, 0.86, 0.74), float3(0.78, 0.74, 0.92), sstep(0.3, 1.0, uv.y)) * grain;
    float2 sunC = float2(0.30 * aspect, 0.72 + 0.01 * sin(time * 0.3));
    float sunD = length(p - sunC);
    col *= 1.0 - 0.18 * sstep(0.12, 0.10, length(p - sunC - float2(0.008, -0.01)));
    col = mix(col, float3(1.0, 0.72, 0.52) * grain, sstep(0.105, 0.10, sunD));
    float3 palette[6] = {
        float3(0.93, 0.70, 0.72), float3(0.86, 0.55, 0.62), float3(0.66, 0.47, 0.64),
        float3(0.44, 0.40, 0.62), float3(0.27, 0.30, 0.50), float3(0.16, 0.19, 0.34)
    };
    for (int i = 0; i < 6; i++) {
        float fi = float(i);
        float sway = 0.006 * sin(time * 0.35 + fi * 1.3);
        float h = 0.66 - fi * 0.095
            + 0.045 * sin(p.x * (2.2 + fi * 0.7) + fi * 1.9 + sway * 20.0)
            + 0.025 * sin(p.x * (5.0 + fi) - fi)
            + 0.012 * (fbm(float2(p.x * 2.0, fi)) - 0.5);
        float shadow = sstep(h + 0.028, h, uv.y) * step(h, uv.y);
        col *= 1.0 - shadow * 0.22;
        if (uv.y < h) {
            float edgeLight = sstep(0.006, 0.0, h - uv.y) * 0.18;
            col = palette[i] * (0.92 + 0.08 * paperGrain(p + fi)) + edgeLight;
        }
    }
    for (int c = 0; c < 4; c++) {
        float fc = float(c);
        float2 cc = float2(fract(fc * 0.27 + time * 0.006 * (1.0 + fc * 0.3)) * (aspect + 0.4) - 0.2, 0.84 - fc * 0.04);
        float2 d = (p - cc) / float2(0.09, 0.025);
        float puff = length(d) - 1.0 + 0.25 * sin(d.x * 6.0);
        float cloudShadow = sstep(0.4, 0.0, length((p - cc - float2(0.006, -0.008)) / float2(0.09, 0.025)) - 1.0);
        col *= 1.0 - cloudShadow * 0.1;
        col = mix(col, float3(1.0, 0.97, 0.95) * grain, sstep(0.05, -0.05, puff));
    }
    return half4(half3(col), 1.0);
}

// ---------------------------------------------------------------------------
// 3. Rose Window: stained glass with light sweeping through.
// ---------------------------------------------------------------------------
[[ stitchable ]] half4 originalRoseWindow(float2 position, half4 color, float2 size, float time) {
    float2 uv = sceneUV(position, size);
    float aspect = size.x / max(size.y, 1.0);
    float2 p = float2((uv.x - 0.5) * aspect, uv.y - 0.5);
    float r = length(p);
    float a = atan2(p.y, p.x);
    float petals = 12.0;
    float sector = fmod(a + 3.14159 + time * 0.01, 6.28318 / petals) - 3.14159 / petals;
    float2 polar = float2(abs(sector) * 3.5, r * 9.0);
    float3 v = voronoi(polar, time, 0.15);
    float lead = sstep(0.06, 0.02, v.y - v.x);
    float ring = sstep(0.0, 0.012, abs(fract(r * 4.5) - 0.5) - 0.47);
    float3 glassA = float3(0.10, 0.25, 0.65), glassB = float3(0.75, 0.12, 0.22), glassC = float3(0.95, 0.70, 0.15), glassD = float3(0.15, 0.55, 0.35);
    float3 glass = v.z < 0.3 ? glassA : (v.z < 0.55 ? glassB : (v.z < 0.8 ? glassC : glassD));
    glass *= 0.75 + 0.35 * fbm(polar * 3.0 + v.z * 10.0);
    float2 lightPos = float2(0.55 * aspect * sin(time * 0.12), 0.25 * cos(time * 0.09));
    float light = 0.55 + 0.9 * exp(-length(p - lightPos) * 2.2) + 0.15 * sin(time * 0.5 + v.z * 20.0);
    float3 col = glass * light;
    col = mix(col, float3(0.03, 0.03, 0.04), clamp(lead + ring, 0.0, 1.0));
    float frame = sstep(0.47, 0.475, r);
    float tracery = sstep(0.0, 0.01, abs(fract(atan2(p.y, p.x) * 3.0 / 3.14159 + r * 2.0) - 0.5) - 0.46);
    float3 stone = float3(0.20, 0.17, 0.15) * (0.6 + 0.6 * fbm(p * 18.0)) * (1.0 - 0.4 * tracery);
    stone *= 0.55 + 0.45 * sstep(1.2, 0.48, r);
    col = mix(col, stone, frame);
    col += float3(1.0, 0.85, 0.6) * 0.08 * exp(-pow((p.x - lightPos.x) * 1.5, 2.0)) * frame;
    return half4(half3(col), 1.0);
}

// ---------------------------------------------------------------------------
// 4. Riso Tide: two-ink risograph print of rolling waves.
// ---------------------------------------------------------------------------
[[ stitchable ]] half4 originalRisoTide(float2 position, half4 color, float2 size, float time) {
    float2 uv = sceneUV(position, size);
    float aspect = size.x / max(size.y, 1.0);
    float2 p = float2(uv.x * aspect, uv.y);
    float3 paper = float3(0.97, 0.94, 0.88) * (0.95 + 0.05 * paperGrain(p));
    float pinkDensity = sstep(0.2, 1.0, uv.y) * 0.55 + sstep(0.16, 0.15, length(p - float2(0.68 * aspect, 0.66))) * 0.95;
    float blueDensity = 0.0;
    for (int i = 0; i < 5; i++) {
        float fi = float(i);
        float crest = 0.44 - fi * 0.085 + 0.04 * sin(p.x * (5.0 + fi) + time * (0.6 + fi * 0.15) + fi * 1.7)
            + 0.02 * sin(p.x * 13.0 - time * 1.1 + fi);
        if (uv.y < crest) {
            blueDensity = 0.35 + fi * 0.13;
            pinkDensity *= 0.3;
        }
        float foam = sstep(0.008, 0.0, abs(uv.y - crest) - 0.002);
        blueDensity = mix(blueDensity, 0.0, foam);
    }
    float freq = 85.0;
    float pink = halftone(p, pinkDensity, 0.26, freq);
    float blue = halftone(p + float2(0.0022, -0.0016), blueDensity, 1.31, freq);
    float3 pinkInk = float3(1.0, 0.36, 0.62), blueInk = float3(0.15, 0.40, 0.85);
    float3 col = paper;
    col *= mix(float3(1.0), pinkInk, pink * 0.92);
    col *= mix(float3(1.0), blueInk, blue * 0.92);
    return half4(half3(col), 1.0);
}

// ---------------------------------------------------------------------------
// 5. Impasto Night: thick swirling brush strokes over sea cliffs.
// ---------------------------------------------------------------------------
[[ stitchable ]] half4 originalImpasto(float2 position, half4 color, float2 size, float time) {
    float2 uv = sceneUV(position, size);
    float aspect = size.x / max(size.y, 1.0);
    float2 p = float2(uv.x * aspect, uv.y);
    float2 q = p + 0.45 * float2(fbm(p * 1.4 + float2(time * 0.02, 0.0)), fbm(p * 1.4 + float2(5.2, -time * 0.02)));
    float swirl = fbm(q * 2.2);
    float3 col = mix(float3(0.06, 0.12, 0.38), float3(0.16, 0.42, 0.72), sstep(0.25, 0.75, swirl));
    col = mix(col, float3(0.85, 0.80, 0.45), sstep(0.62, 0.85, swirl) * 0.6);
    for (int k = 0; k < 4; k++) {
        float fk = float(k);
        float2 c = float2((0.15 + fk * 0.24) * aspect, 0.72 + 0.08 * sin(fk * 2.1));
        float d = length(p - c);
        float rings = 0.5 + 0.5 * sin(d * 90.0 - time * 0.8 + fk);
        float halo = exp(-d * (9.0 + fk * 2.0));
        col = mix(col, float3(1.0, 0.86, 0.35), halo * (0.55 + 0.45 * rings));
        col = mix(col, float3(1.0, 0.95, 0.70), sstep(0.022 + fk * 0.004, 0.012, d));
    }
    float cliff = 0.28 + 0.10 * sstep(0.2 * aspect, 0.9 * aspect, p.x) + 0.04 * fbm(float2(p.x * 3.0, 1.0));
    if (uv.y < cliff) {
        float sea = sstep(0.0, 0.18, uv.y);
        col = mix(float3(0.04, 0.08, 0.18), float3(0.10, 0.18, 0.30), sea);
        col = p.x > 0.35 * aspect ? mix(col, float3(0.10, 0.07, 0.08), step(0.16, uv.y)) : col;
    }
    float angle = 6.2831 * fbm(q * 0.9 + 3.0);
    float stroke = dot(p, float2(-sin(angle), cos(angle))) * 140.0 + fbm(p * 25.0) * 6.0;
    float bristles = 0.5 + 0.5 * sin(stroke);
    float thickness = 0.82 + 0.28 * bristles + 0.08 * (valueNoise(p * 300.0) - 0.5);
    col *= thickness;
    col += 0.06 * pow(bristles, 6.0);
    return half4(half3(col), 1.0);
}

// ---------------------------------------------------------------------------
// 6. Bauhaus Shift: geometric tiles that rotate and swap on a rhythm.
// ---------------------------------------------------------------------------
[[ stitchable ]] half4 originalBauhaus(float2 position, half4 color, float2 size, float time) {
    float2 uv = sceneUV(position, size);
    float aspect = size.x / max(size.y, 1.0);
    float rows = 5.0;
    float2 g = float2(uv.x * aspect, uv.y) * rows;
    float2 cell = floor(g);
    float2 local = fract(g) - 0.5;
    float beat = floor(time / 3.0);
    float phase = fract(time / 3.0);
    float ease = sstep(0.0, 0.35, phase);
    float h = hash21(cell + beat * 0.37);
    float hPrev = hash21(cell + (beat - 1.0) * 0.37);
    float rotation = 1.5708 * (floor(hPrev * 4.0) + ease * step(0.5, h));
    float2 l = rotate2(local, rotation);
    float3 cream = float3(0.95, 0.91, 0.82) * (0.95 + 0.05 * paperGrain(g * 0.2));
    float3 palette[4] = { float3(0.86, 0.20, 0.16), float3(0.98, 0.76, 0.12), float3(0.12, 0.26, 0.62), float3(0.10, 0.10, 0.11) };
    float3 bg = palette[int(hash21(cell + 9.0) * 4.0)];
    float3 fg = palette[int(hash21(cell + beat + 2.0) * 4.0)];
    if (all(bg == fg)) { fg = cream; }
    bool creamBg = hash21(cell + 5.0) > 0.45;
    float3 col = creamBg ? cream : bg;
    int shape = int(h * 4.0);
    float mask = 0.0;
    if (shape == 0) { mask = sstep(1.01, 0.99, length(l - float2(-0.5, -0.5))); }
    else if (shape == 1) { mask = sstep(0.51, 0.49, length(l - float2(0.0, -0.5))) ; }
    else if (shape == 2) { mask = sstep(0.36, 0.34, length(l)); }
    else { mask = step(l.y, l.x); }
    col = mix(col, creamBg ? fg : cream, mask);
    float border = sstep(0.485, 0.495, max(abs(local.x), abs(local.y)));
    col = mix(col, float3(0.08, 0.08, 0.09), border);
    return half4(half3(col), 1.0);
}

// ---------------------------------------------------------------------------
// 7. Chrome Bloom: iridescent thin-film liquid.
// ---------------------------------------------------------------------------
[[ stitchable ]] half4 originalChromeBloom(float2 position, half4 color, float2 size, float time) {
    float2 uv = sceneUV(position, size);
    float aspect = size.x / max(size.y, 1.0);
    float2 p = float2(uv.x * aspect, uv.y) * 1.6;
    float2 w1 = float2(fbm(p + float2(0.0, time * 0.05)), fbm(p + float2(5.2, 1.3) - time * 0.04));
    float2 w2 = float2(fbm(p + 3.0 * w1 + float2(1.7, 9.2)), fbm(p + 3.0 * w1 + float2(8.3, 2.8) + time * 0.03));
    float f = fbm(p + 3.5 * w2);
    float thickness = f * 2.4 + length(w2) * 0.8 + time * 0.03;
    // Pearl and oil-slick tones rather than raw rainbow.
    float3 film = 0.5 + 0.5 * cos(6.2831 * (thickness * 0.8 + float3(0.55, 0.62, 0.78)));
    film = mix(float3(0.78, 0.80, 0.86), film, 0.55);
    float e = 0.01;
    float fx = fbm(p + float2(e, 0.0) + 3.5 * w2) - f;
    float fy = fbm(p + float2(0.0, e) + 3.5 * w2) - f;
    float3 n = normalize(float3(-fx * 60.0, -fy * 60.0, 1.0));
    float spec = pow(clamp(dot(n, normalize(float3(0.4, 0.6, 0.7))), 0.0, 1.0), 40.0);
    float3 col = mix(float3(0.03, 0.03, 0.05), film, sstep(0.30, 0.70, f));
    col = col * (0.45 + 0.55 * n.z) + spec * 0.8;
    col = pow(col, float3(1.15));
    return half4(half3(col), 1.0);
}

// ---------------------------------------------------------------------------
// 8. Amber Terminal: 1-bit dithered seascape on an old CRT.
// ---------------------------------------------------------------------------
[[ stitchable ]] half4 originalAmberTerminal(float2 position, half4 color, float2 size, float time) {
    float pixelSize = max(size.y / 180.0, 2.0);
    float2 pixel = floor(position / pixelSize);
    float2 uv = sceneUV(pixel * pixelSize, size);
    float aspect = size.x / max(size.y, 1.0);
    float2 p = float2(uv.x * aspect, uv.y);
    float horizon = 0.42;
    float sun = exp(-length(p - float2(0.5 * aspect, horizon + 0.12)) * 7.0);
    float value = mix(0.15, 0.55, sstep(horizon, 1.0, 1.0 - uv.y + horizon)) + sun * 0.9;
    float clouds = sstep(0.55, 0.62, fbm(float2(p.x * 1.6 + time * 0.02, p.y * 6.0)));
    value = mix(value, value + 0.25, clouds * step(horizon + 0.05, uv.y));
    if (uv.y < horizon) {
        float depth = (horizon - uv.y) / horizon;
        float waves = 0.5 + 0.5 * sin(p.x * 50.0 / (depth + 0.08) + time * 1.5 + depth * 20.0);
        float path = exp(-pow((p.x - 0.5 * aspect) * (4.0 + depth * 6.0), 2.0));
        value = mix(0.35, 0.05, depth) + path * waves * 0.7;
    }
    float levels = 3.0;
    float dithered = floor(value * levels + bayer4(pixel)) / levels;
    float3 palette = mix(float3(0.07, 0.03, 0.01), float3(1.0, 0.70, 0.22), clamp(dithered, 0.0, 1.0));
    float scan = 0.9 + 0.1 * sin(position.y * 3.14159 / max(pixelSize * 0.5, 1.0));
    float2 c = uv - 0.5;
    float vignette = 1.0 - dot(c, c) * 0.9;
    return half4(half3(palette * scan * vignette), 1.0);
}
