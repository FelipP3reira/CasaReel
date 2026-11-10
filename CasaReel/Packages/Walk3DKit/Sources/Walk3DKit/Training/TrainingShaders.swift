/// Differentiable tile rasterizer for 3D Gaussian Splatting (Kerbl et al. 2023), view-independent color.
///
/// Per Gaussian, 16 floats (`GaussianModel.stride`): position xyz · log-scale xyz · rotation wxyz (unnormalized)
/// · color logits rgb · opacity logit · 2 unused. Camera axes follow OpenCV (x right, y down, z forward).
/// The CPU sorts by depth and bins into 16×16 tiles between `preprocess` and `rasterizeForward`.
enum TrainingShaders {
    static let source = """
    #include <metal_stdlib>
    using namespace metal;

    constant uint TILE = 16;
    constant uint BATCH = 256;
    constant uint SCREEN_STRIDE = 12;
    constant uint STRIDE = 16;

    struct View {
        float4 r0, r1, r2;      // world→camera rows, translation in w
        float4 intrinsics;      // fx, fy, cx, cy
        uint4 size;             // width, height, tilesX, tilesY
        float4 background;      // rgb, 1 / (3 · pixels) in w
    };

    struct Projected {
        float4 a;               // mean x, mean y, opacity, depth
        float4 b;               // conic a, b, c, radius (0 = culled)
        float4 color;
    };

    struct Step {
        float4 lrA;             // position, scale, rotation, color
        float4 lrB;             // opacity, 1 − β1^t, 1 − β2^t, apply
        uint4 counts;           // gaussians
    };

    struct Geometry {
        float3x3 W, R, M, sigma, J, T;
        float3 c, s;
        float4 q;               // normalized
        float qLength;
        float2 mean;
        float s00, s01, s11;    // 2D covariance with the low-pass filter
    };

    inline float sigmoid(float x) { return 1.0 / (1.0 + exp(-x)); }

    inline float3x3 rotation(float4 q) {
        float w = q.x, x = q.y, y = q.z, z = q.w;
        return float3x3(float3(1 - 2 * (y * y + z * z), 2 * (x * y + w * z), 2 * (x * z - w * y)),
                        float3(2 * (x * y - w * z), 1 - 2 * (x * x + z * z), 2 * (y * z + w * x)),
                        float3(2 * (x * z + w * y), 2 * (y * z - w * x), 1 - 2 * (x * x + y * y)));
    }

    inline bool project(device const float *p, constant View &view, thread Geometry &g) {
        g.W = transpose(float3x3(view.r0.xyz, view.r1.xyz, view.r2.xyz));
        float3 position = float3(p[0], p[1], p[2]);
        g.c = g.W * position + float3(view.r0.w, view.r1.w, view.r2.w);
        if (g.c.z < 0.05) { return false; }
        g.s = exp(float3(p[3], p[4], p[5]));
        float4 q = float4(p[6], p[7], p[8], p[9]);
        g.qLength = max(length(q), 1e-8);
        g.q = q / g.qLength;
        g.R = rotation(g.q);
        g.M = g.R * float3x3(float3(g.s.x, 0, 0), float3(0, g.s.y, 0), float3(0, 0, g.s.z));
        g.sigma = g.M * transpose(g.M);
        float fx = view.intrinsics.x, fy = view.intrinsics.y, z = g.c.z;
        g.J = float3x3(float3(fx / z, 0, 0), float3(0, fy / z, 0),
                       float3(-fx * g.c.x / (z * z), -fy * g.c.y / (z * z), 0));
        g.T = g.J * g.W;
        float3x3 projected = g.T * g.sigma * transpose(g.T);
        g.s00 = projected[0][0] + 0.3;
        g.s01 = projected[1][0];
        g.s11 = projected[1][1] + 0.3;
        g.mean = float2(fx * g.c.x / z + view.intrinsics.z, fy * g.c.y / z + view.intrinsics.w);
        return g.s00 * g.s11 - g.s01 * g.s01 > 1e-12;
    }

    kernel void preprocess(device const float *params [[buffer(0)]],
                           device Projected *projected [[buffer(1)]],
                           device uint4 *rects [[buffer(2)]],
                           constant View &view [[buffer(3)]],
                           constant uint &count [[buffer(4)]],
                           uint id [[thread_position_in_grid]]) {
        if (id >= count) { return; }
        rects[id] = uint4(0);
        projected[id].b = float4(0);
        device const float *p = params + id * STRIDE;
        Geometry g;
        if (!project(p, view, g)) { return; }
        float det = g.s00 * g.s11 - g.s01 * g.s01;
        float mid = 0.5 * (g.s00 + g.s11);
        float lambda = mid + sqrt(max(0.1, mid * mid - det));
        float radius = ceil(3.0 * sqrt(lambda));
        int tilesX = int(view.size.z), tilesY = int(view.size.w);
        int minX = clamp(int(floor((g.mean.x - radius) / TILE)), 0, tilesX);
        int maxX = clamp(int(floor((g.mean.x + radius) / TILE)) + 1, 0, tilesX);
        int minY = clamp(int(floor((g.mean.y - radius) / TILE)), 0, tilesY);
        int maxY = clamp(int(floor((g.mean.y + radius) / TILE)) + 1, 0, tilesY);
        if (minX >= maxX || minY >= maxY) { return; }
        rects[id] = uint4(minX, minY, maxX, maxY);
        projected[id].a = float4(g.mean, sigmoid(p[13]), g.c.z);
        projected[id].b = float4(g.s11 / det, -g.s01 / det, g.s00 / det, radius);
        projected[id].color = float4(sigmoid(p[10]), sigmoid(p[11]), sigmoid(p[12]), 0);
    }

    kernel void rasterizeForward(constant View &view [[buffer(0)]],
                                 device const uint2 *ranges [[buffer(1)]],
                                 device const uint *list [[buffer(2)]],
                                 device const Projected *projected [[buffer(3)]],
                                 device float4 *pixelState [[buffer(4)]],
                                 device uint *pixelLast [[buffer(5)]],
                                 device float *pixelLoss [[buffer(6)]],
                                 constant uint &slice [[buffer(7)]],
                                 texture2d_array<float, access::read> targets [[texture(0)]],
                                 uint2 group [[threadgroup_position_in_grid]],
                                 uint2 local [[thread_position_in_threadgroup]],
                                 uint lane [[thread_index_in_threadgroup]]) {
        threadgroup float4 sharedA[BATCH];
        threadgroup float4 sharedB[BATCH];
        threadgroup float4 sharedC[BATCH];
        uint width = view.size.x, height = view.size.y;
        uint2 pixel = group * TILE + local;
        bool inside = pixel.x < width && pixel.y < height;
        uint2 range = ranges[group.y * view.size.z + group.x];
        uint todo = range.y - range.x;
        float2 point = float2(pixel);
        float T = 1;
        float3 color = 0;
        uint contributor = 0, last = 0;
        bool done = !inside;
        for (uint start = 0; start < todo; start += BATCH) {
            threadgroup_barrier(mem_flags::mem_threadgroup);
            if (start + lane < todo) {
                Projected g = projected[list[range.x + start + lane]];
                sharedA[lane] = g.a; sharedB[lane] = g.b; sharedC[lane] = g.color;
            }
            threadgroup_barrier(mem_flags::mem_threadgroup);
            uint n = min(BATCH, todo - start);
            for (uint j = 0; j < n && !done; j++) {
                contributor++;
                float4 A = sharedA[j], B = sharedB[j];
                float2 d = point - A.xy;
                float power = -0.5 * (B.x * d.x * d.x + B.z * d.y * d.y) - B.y * d.x * d.y;
                if (power > 0) { continue; }
                float alpha = min(0.99, A.z * exp(power));
                if (alpha < 1.0 / 255.0) { continue; }
                float nextT = T * (1 - alpha);
                if (nextT < 0.0001) { done = true; continue; }
                color += sharedC[j].rgb * alpha * T;
                T = nextT;
                last = contributor;
            }
        }
        if (!inside) { return; }
        uint index = pixel.y * width + pixel.x;
        float3 diff = color + T * view.background.rgb - targets.read(pixel, slice).rgb;
        pixelState[index] = float4(sign(diff) * view.background.w, T);
        pixelLast[index] = last;
        pixelLoss[index] = abs(diff.r) + abs(diff.g) + abs(diff.b);
    }

    kernel void rasterizeBackward(constant View &view [[buffer(0)]],
                                  device const uint2 *ranges [[buffer(1)]],
                                  device const uint *list [[buffer(2)]],
                                  device const Projected *projected [[buffer(3)]],
                                  device const float4 *pixelState [[buffer(4)]],
                                  device const uint *pixelLast [[buffer(5)]],
                                  device atomic_float *screenGrads [[buffer(6)]],
                                  uint2 group [[threadgroup_position_in_grid]],
                                  uint2 local [[thread_position_in_threadgroup]],
                                  uint lane [[thread_index_in_threadgroup]]) {
        threadgroup float4 sharedA[BATCH];
        threadgroup float4 sharedB[BATCH];
        threadgroup float4 sharedC[BATCH];
        threadgroup uint sharedID[BATCH];
        uint width = view.size.x, height = view.size.y;
        uint2 pixel = group * TILE + local;
        bool inside = pixel.x < width && pixel.y < height;
        uint index = inside ? pixel.y * width + pixel.x : 0;
        uint2 range = ranges[group.y * view.size.z + group.x];
        uint todo = range.y - range.x;
        float4 state = inside ? pixelState[index] : float4(0);
        uint last = inside ? pixelLast[index] : 0;
        float3 dLdC = state.rgb;
        float finalT = state.w, T = state.w;
        float backgroundDot = dot(view.background.rgb, dLdC);
        float3 accum = 0, lastColor = 0;
        float lastAlpha = 0;
        float2 point = float2(pixel);
        // Back to front over the same list the forward pass walked front to back.
        for (uint start = 0; start < todo; start += BATCH) {
            threadgroup_barrier(mem_flags::mem_threadgroup);
            if (start + lane < todo) {
                uint id = list[range.x + todo - 1 - (start + lane)];
                Projected g = projected[id];
                sharedID[lane] = id; sharedA[lane] = g.a; sharedB[lane] = g.b; sharedC[lane] = g.color;
            }
            threadgroup_barrier(mem_flags::mem_threadgroup);
            uint n = min(BATCH, todo - start);
            for (uint j = 0; j < n; j++) {
                uint k = todo - 1 - (start + j);
                float4 A = sharedA[j], B = sharedB[j];
                float3 col = sharedC[j].rgb;
                float2 d = point - A.xy;
                float power = -0.5 * (B.x * d.x * d.x + B.z * d.y * d.y) - B.y * d.x * d.y;
                float G = exp(min(power, 0.0));
                float alpha = min(0.99, A.z * G);
                bool valid = inside && k < last && power <= 0 && alpha >= 1.0 / 255.0;
                float g0 = 0, g1 = 0, g2 = 0, g3 = 0, g4 = 0, g5 = 0;
                float3 gColor = 0;
                if (valid) {
                    T = T / (1 - alpha);
                    accum = lastAlpha * lastColor + (1 - lastAlpha) * accum;
                    lastColor = col;
                    float dLdAlpha = dot(col - accum, dLdC) * T;
                    lastAlpha = alpha;
                    dLdAlpha += (-finalT / (1 - alpha)) * backgroundDot;
                    float dLdPower = dLdAlpha * A.z * G;
                    g0 = dLdPower * (B.x * d.x + B.y * d.y);
                    g1 = dLdPower * (B.z * d.y + B.y * d.x);
                    g2 = dLdPower * (-0.5 * d.x * d.x);
                    g3 = dLdPower * (-d.x * d.y);
                    g4 = dLdPower * (-0.5 * d.y * d.y);
                    g5 = G * dLdAlpha;
                    gColor = alpha * T * dLdC;
                }
                // One atomic per SIMD group instead of one per pixel.
                if (simd_any(valid)) {
                    float s0 = simd_sum(g0), s1 = simd_sum(g1), s2 = simd_sum(g2), s3 = simd_sum(g3), s4 = simd_sum(g4), s5 = simd_sum(g5);
                    float3 sc = float3(simd_sum(gColor.r), simd_sum(gColor.g), simd_sum(gColor.b));
                    if (simd_is_first()) {
                        device atomic_float *out = screenGrads + sharedID[j] * SCREEN_STRIDE;
                        atomic_fetch_add_explicit(out + 0, s0, memory_order_relaxed);
                        atomic_fetch_add_explicit(out + 1, s1, memory_order_relaxed);
                        atomic_fetch_add_explicit(out + 2, s2, memory_order_relaxed);
                        atomic_fetch_add_explicit(out + 3, s3, memory_order_relaxed);
                        atomic_fetch_add_explicit(out + 4, s4, memory_order_relaxed);
                        atomic_fetch_add_explicit(out + 5, s5, memory_order_relaxed);
                        atomic_fetch_add_explicit(out + 6, sc.r, memory_order_relaxed);
                        atomic_fetch_add_explicit(out + 7, sc.g, memory_order_relaxed);
                        atomic_fetch_add_explicit(out + 8, sc.b, memory_order_relaxed);
                    }
                }
            }
        }
    }

    /// Screen-space gradients → parameter gradients, then one Adam step.
    kernel void backwardStep(device float *params [[buffer(0)]],
                             device const Projected *projected [[buffer(1)]],
                             device const float *screenGrads [[buffer(2)]],
                             device float *grads [[buffer(3)]],
                             device float *m [[buffer(4)]],
                             device float *v [[buffer(5)]],
                             device float2 *densify [[buffer(6)]],
                             constant View &view [[buffer(7)]],
                             constant Step &step [[buffer(8)]],
                             uint id [[thread_position_in_grid]]) {
        if (id >= step.counts.x) { return; }
        device float *p = params + id * STRIDE;
        float gr[14];
        for (uint i = 0; i < 14; i++) { gr[i] = 0; }
        Geometry g;
        if (projected[id].b.w > 0 && project(p, view, g)) {
            device const float *sg = screenGrads + id * SCREEN_STRIDE;
            float2 dMean = float2(sg[0], sg[1]);
            float ga = sg[2], gb = sg[3], gc = sg[4];
            float det = g.s00 * g.s11 - g.s01 * g.s01;
            float a = g.s11 / det, b = -g.s01 / det, c = g.s00 / det;
            // conic = Σ2D⁻¹  ⇒  dL/dΣ2D = −A · dL/dA · A (b sits in two entries).
            float p00 = ga * a + 0.5 * gb * b, p01 = ga * b + 0.5 * gb * c;
            float p10 = 0.5 * gb * a + gc * b, p11 = 0.5 * gb * b + gc * c;
            float q00 = a * p00 + b * p10, q01 = a * p01 + b * p11;
            float q10 = b * p00 + c * p10, q11 = b * p01 + c * p11;
            float gS01 = -0.5 * (q01 + q10);
            float3x3 G2 = float3x3(float3(-q00, gS01, 0), float3(gS01, -q11, 0), float3(0));
            float3x3 gSigma = transpose(g.T) * G2 * g.T;
            float3x3 gJ = (2.0 * G2 * g.T * g.sigma) * transpose(g.W);
            float fx = view.intrinsics.x, fy = view.intrinsics.y;
            float x = g.c.x, y = g.c.y, z = g.c.z, z2 = z * z, z3 = z2 * z;
            float3 gCam;
            gCam.x = gJ[2][0] * (-fx / z2) + dMean.x * fx / z;
            gCam.y = gJ[2][1] * (-fy / z2) + dMean.y * fy / z;
            gCam.z = gJ[0][0] * (-fx / z2) + gJ[2][0] * (2 * fx * x / z3) + gJ[1][1] * (-fy / z2) + gJ[2][1] * (2 * fy * y / z3)
                   - dMean.x * fx * x / z2 - dMean.y * fy * y / z2;
            float3 gPosition = transpose(g.W) * gCam;
            float3x3 gM = 2.0 * gSigma * g.M;
            float3 gScale = float3(dot(g.R[0], gM[0]), dot(g.R[1], gM[1]), dot(g.R[2], gM[2]));
            float3x3 gR = float3x3(gM[0] * g.s.x, gM[1] * g.s.y, gM[2] * g.s.z);
            // G(row, col) = gR[col][row]
            float G00 = gR[0][0], G01 = gR[1][0], G02 = gR[2][0];
            float G10 = gR[0][1], G11 = gR[1][1], G12 = gR[2][1];
            float G20 = gR[0][2], G21 = gR[1][2], G22 = gR[2][2];
            float w = g.q.x, qx = g.q.y, qy = g.q.z, qz = g.q.w;
            float4 gq;
            gq.x = 2 * (-qz * G01 + qy * G02 + qz * G10 - qx * G12 - qy * G20 + qx * G21);
            gq.y = 2 * (qy * G01 + qz * G02 + qy * G10 - 2 * qx * G11 - w * G12 + qz * G20 + w * G21 - 2 * qx * G22);
            gq.z = 2 * (-2 * qy * G00 + qx * G01 + w * G02 + qx * G10 + qz * G12 - w * G20 + qz * G21 - 2 * qy * G22);
            gq.w = 2 * (-2 * qz * G00 - w * G01 + qx * G02 + w * G10 - 2 * qz * G11 + qy * G12 + qx * G20 + qy * G21);
            gq = (gq - g.q * dot(g.q, gq)) / g.qLength;
            float3 color = projected[id].color.rgb;
            float opacity = projected[id].a.z;
            gr[0] = gPosition.x; gr[1] = gPosition.y; gr[2] = gPosition.z;
            gr[3] = gScale.x * g.s.x; gr[4] = gScale.y * g.s.y; gr[5] = gScale.z * g.s.z;
            gr[6] = gq.x; gr[7] = gq.y; gr[8] = gq.z; gr[9] = gq.w;
            gr[10] = sg[6] * color.r * (1 - color.r);
            gr[11] = sg[7] * color.g * (1 - color.g);
            gr[12] = sg[8] * color.b * (1 - color.b);
            gr[13] = sg[5] * opacity * (1 - opacity);
            // Densification statistic: the gradient in normalized device coordinates, as in the paper.
            densify[id] += float2(length(dMean * 0.5 * float2(view.size.xy)), 1);
        }
        device float *gOut = grads + id * STRIDE;
        for (uint i = 0; i < 14; i++) { gOut[i] = gr[i]; }
        if (step.lrB.w == 0) { return; }
        device float *mi = m + id * STRIDE;
        device float *vi = v + id * STRIDE;
        for (uint i = 0; i < 14; i++) {
            float lr = i < 3 ? step.lrA.x : i < 6 ? step.lrA.y : i < 10 ? step.lrA.z : i < 13 ? step.lrA.w : step.lrB.x;
            mi[i] = 0.9 * mi[i] + 0.1 * gr[i];
            vi[i] = 0.999 * vi[i] + 0.001 * gr[i] * gr[i];
            p[i] -= lr * (mi[i] / step.lrB.y) / (sqrt(vi[i] / step.lrB.z) + 1e-15);
        }
    }
    """
}
