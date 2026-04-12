#include <metal_stdlib>
using namespace metal;

struct Uniforms {
    float2 resolution;
    float time;
    float loopDuration;
};

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

constant float kTau = 6.28318530718;

// Lightweight 1D hash used for per-stripe variation without textures.
float hash11(float value) {
    value = fract(value * 0.1031);
    value *= value + 33.33;
    value *= value + value;
    return fract(value);
}

// Small saturation lift keeps the palette vivid after tonemapping.
float3 saturateColor(float3 color, float amount) {
    float luminance = dot(color, float3(0.2126, 0.7152, 0.0722));
    return mix(float3(luminance), color, amount);
}

// Reusable soft band mask for the structured background ribbons.
float bandMask(float value, float width) {
    float distanceToCenter = abs(fract(value) - 0.5);
    return smoothstep(width, 0.0, distanceToCenter);
}

int positiveModulo(int value, int modulus) {
    int result = value % modulus;
    return result < 0 ? result + modulus : result;
}

int stripeFamilyIndex(float stripeIndex) {
    constexpr int familyCount = 6;

    int ordinal = int(stripeIndex);
    int group = int(floor(stripeIndex / float(familyCount)));
    int rotation = int(floor(hash11(float(group) * 13.17 + 0.91) * float(familyCount)));

    // Adding the same rotation to a whole group preserves the guarantee that
    // neighboring stripe indices never map to the same family.
    return positiveModulo(ordinal + rotation, familyCount);
}

float3 stripeFamilyColor(int family, float detailSeed, float colorSeed) {
    float3 deepBlue = float3(0.06, 0.24, 0.98);
    float3 violet = float3(0.54, 0.22, 1.00);
    float3 cobalt = float3(0.08, 0.50, 1.00);
    float3 azure = float3(0.14, 0.72, 1.00);
    float3 cyan = float3(0.10, 0.94, 1.00);
    float3 ice = float3(0.84, 0.98, 1.00);

    float3 base = deepBlue;
    if (family == 1) {
        base = violet;
    } else if (family == 2) {
        base = cobalt;
    } else if (family == 3) {
        base = azure;
    } else if (family == 4) {
        base = cyan;
    } else if (family == 5) {
        base = ice;
    }

    float frostMix = 0.04 + detailSeed * 0.10;
    float3 color = mix(base, ice, frostMix);
    color = mix(color, float3(0.04, 0.82, 1.00), detailSeed * 0.09);

    color *= 1.00 + colorSeed * 0.34;
    return saturate(saturateColor(color, 1.30));
}

vertex VertexOut fullscreenVertex(uint vertexID [[vertex_id]]) {
    float2 positions[3] = {
        float2(-1.0, -1.0),
        float2( 3.0, -1.0),
        float2(-1.0,  3.0)
    };

    VertexOut out;
    out.position = float4(positions[vertexID], 0.0, 1.0);
    out.uv = positions[vertexID] * 0.5 + 0.5;
    return out;
}

fragment float4 lightBeamsFragment(
    VertexOut in [[stage_in]],
    constant Uniforms& uniforms [[buffer(0)]]
) {
    float2 resolution = max(uniforms.resolution, float2(1.0));
    float loopDuration = max(uniforms.loopDuration, 1.0);
    float loopTime = fract(uniforms.time / loopDuration);
    float loopAngle = loopTime * kTau;

    float2 uv = in.uv;
    float2 position = uv * 2.0 - 1.0;
    position.x *= resolution.x / resolution.y;

    // Beam direction defines the diagonal streak angle.
    float2 beamDirection = normalize(float2(0.58, -1.0));
    float2 beamNormal = float2(-beamDirection.y, beamDirection.x);

    // Project the screen position onto the normal to split the image into stripes.
    float along = dot(position, beamDirection);
    float cross = dot(position, beamNormal);

    // All temporal terms are expressed through loopAngle with integer
    // multipliers, so the frame at t=0 matches the frame at t=loopDuration.
    float flowWarp =
        0.11 * sin(along * 2.2 - loopAngle * 2.0) +
        0.05 * sin(dot(position, float2(1.3, 1.7)) * 3.9 + loopAngle * 3.0);

    float stripeDensity = 30.0;
    float stripeCoordinate = (cross + flowWarp * 0.08) * stripeDensity;
    float stripeBase = floor(stripeCoordinate);

    // Layer a few broad diagonal ribbons under the fine streaks so the frame
    // stays dimensional without falling into a soft blur wash.
    float backgroundMix = 0.5 + 0.5 * sin(cross * 1.20 - along * 0.42 + loopAngle);
    float ribbonA = bandMask(cross * 1.85 - along * 0.28 + loopAngle * 1.0, 0.075);
    float ribbonB = bandMask(-cross * 1.35 - along * 0.36 - loopAngle * 2.0, 0.095);
    float ribbonC = bandMask(cross * 3.60 + along * 0.12 + loopAngle * 3.0, 0.035);
    float ribbonBreakA = 0.50 + 0.50 * sin(along * 7.2 + cross * 1.7 + loopAngle * 4.0);
    float ribbonBreakB = 0.50 + 0.50 * sin(along * 5.4 - cross * 2.1 - loopAngle * 5.0);
    float ribbonBreakC = 0.50 + 0.50 * sin(along * 9.0 + cross * 3.6 + loopAngle * 6.0);
    ribbonA *= 0.20 + 0.45 * ribbonBreakA;
    ribbonB *= 0.18 + 0.42 * ribbonBreakB;
    ribbonC *= 0.22 + 0.38 * ribbonBreakC;
    float backgroundRipple = 0.5 + 0.5 * sin(cross * 4.8 - along * 1.1 + loopAngle * 2.0);

    float3 color = mix(float3(0.024, 0.100, 0.340), float3(0.070, 0.250, 0.840), backgroundMix);
    color = mix(color, color + float3(0.020, 0.094, 0.280), ribbonA * 0.22);
    color = mix(color, color + float3(0.018, 0.130, 0.330), ribbonB * 0.18);
    color = mix(color, color + float3(0.030, 0.220, 0.500), ribbonC * 0.15);
    color += float3(0.014, 0.062, 0.145) * backgroundRipple;
    color = mix(color, float3(0.110, 0.620, 0.960), ribbonC * 0.05);

    // Sample a few neighboring stripes so each pixel gets a sharp core and a
    // restrained glow contribution from nearby beams.
    for (int offset = -2; offset <= 2; ++offset) {
        float stripeIndex = stripeBase + float(offset);
        float distToCenter = stripeCoordinate - (stripeIndex + 0.5);

        float colorSeed = hash11(stripeIndex * 17.13 + 0.71);
        float speedSeed = hash11(stripeIndex * 29.77 + 2.41);
        float phaseSeed = hash11(stripeIndex * 43.97 + 9.11);
        float widthSeed = hash11(stripeIndex * 57.31 + 5.17);
        float detailSeed = hash11(stripeIndex * 71.83 + 1.93);
        float presenceSeed = hash11(stripeIndex * 89.43 + 4.37);

        float beamPresence = mix(0.60, 1.0, smoothstep(0.34, 0.92, presenceSeed));

        float coreWidth = mix(0.070, 0.125, widthSeed);
        float haloWidth = coreWidth * mix(1.30, 1.90, detailSeed);

        float core = exp(-pow(abs(distToCenter) / coreWidth, 1.05));
        float halo = exp(-pow(abs(distToCenter) / haloWidth, 1.55));

        float stripeSpeed = 1.0 + floor(speedSeed * 5.0);
        float stripePhase = phaseSeed * kTau;
        float pulseFrequency = mix(10.0, 16.5, detailSeed);
        float pulseTravel = 3.0 + stripeSpeed;
        float secondaryTravel = 2.0 + floor(detailSeed * 4.0);
        float shimmerTravel = 1.0 + floor(colorSeed * 3.0);

        // Pulses travel along each stripe; pow(sin, 8) creates sharp bright packets.
        float pulseWave = along * pulseFrequency - loopAngle * pulseTravel + stripePhase;
        float pulse = pow(max(0.0, sin(pulseWave)), 8.0);
        float secondaryWave = along * (pulseFrequency * 0.58) - loopAngle * secondaryTravel + stripePhase * 1.5;
        float pulseSecondary = 0.12 * pow(max(0.0, sin(secondaryWave)), 8.0);

        float baseBrightness = mix(0.035, 0.075, colorSeed);
        float shimmer = 0.94 + 0.06 * sin(along * 7.5 + stripePhase + loopAngle * shimmerTravel);

        int family = stripeFamilyIndex(stripeIndex);
        float3 stripeColor = stripeFamilyColor(family, detailSeed, colorSeed);

        float intensity = halo * (0.006 + baseBrightness * 0.36) + core * (0.34 + pulse * 1.65 + pulseSecondary * 0.90);
        intensity *= shimmer;
        intensity *= beamPresence;

        color += stripeColor * intensity;
        color += stripeColor * pulse * core * 0.24;
    }

    float edge = max(abs(position.x) * 0.78, abs(position.y));
    float edgeFade = 1.0 - smoothstep(1.02, 1.48, edge);
    color *= 0.98 + 0.05 * edgeFade;
    color += float3(0.018, 0.030, 0.068);

    // Exponential tonemapping keeps the glow bright without clipping harshly.
    color = 1.0 - exp(-color * 1.22);
    color = pow(color, float3(0.88));
    color = saturate(saturateColor(color, 1.40));

    return float4(color, 1.0);
}
