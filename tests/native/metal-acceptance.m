// Build only if Apple's Command Line Tools are already installed:
// xcrun clang -fobjc-arc -framework Foundation -framework Metal metal-acceptance.m -o metal-acceptance
// Run as the logged-in guest user, without sudo. No settings or driver files are changed.
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

static BOOL finish(id<MTLCommandBuffer> cb, NSMutableDictionary *r) {
    if (!cb) { r[@"error"] = @"No command buffer"; return NO; }
    NSTimeInterval start = [NSDate timeIntervalSinceReferenceDate];
    [cb commit];
    while (cb.status < MTLCommandBufferStatusCompleted &&
           [NSDate timeIntervalSinceReferenceDate] - start < 60.0) usleep(10000);
    r[@"command_status"] = @(cb.status);
    r[@"elapsed_seconds"] = @([NSDate timeIntervalSinceReferenceDate] - start);
    if (cb.error) r[@"command_error"] = cb.error.localizedDescription;
    if (cb.status != MTLCommandBufferStatusCompleted || cb.error) {
        r[@"error"] = @"GPU command did not complete successfully within 60 seconds";
        return NO;
    }
    return YES;
}

static NSMutableDictionary *copyTest(id<MTLDevice> dev) {
    NSMutableDictionary *r = [@{@"pass": @NO, @"bytes": @4096} mutableCopy];
    const NSUInteger bytes = 4096;
    id<MTLBuffer> src = [dev newBufferWithLength:bytes options:MTLResourceStorageModeShared];
    id<MTLBuffer> gpu = [dev newBufferWithLength:bytes options:MTLResourceStorageModePrivate];
    id<MTLBuffer> dst = [dev newBufferWithLength:bytes options:MTLResourceStorageModeShared];
    if (!src || !gpu || !dst || !src.contents || !dst.contents) {
        r[@"error"] = @"Buffer allocation or CPU mapping failed"; return r;
    }
    r[@"private_storage_mode"] = @(gpu.storageMode);
    if (gpu.storageMode != MTLStorageModePrivate) { r[@"error"] = @"Private storage not honored"; return r; }
    uint32_t *p = src.contents;
    for (NSUInteger i = 0; i < bytes / 4; ++i) p[i] = (uint32_t)(i * 2654435761u + 0x12345678u);
    memset(dst.contents, 0, bytes);
    id<MTLCommandQueue> queue = [dev newCommandQueue];
    id<MTLCommandBuffer> cb = [queue commandBuffer];
    id<MTLBlitCommandEncoder> enc = [cb blitCommandEncoder];
    if (!enc) { r[@"error"] = @"No blit encoder"; return r; }
    [enc copyFromBuffer:src sourceOffset:0 toBuffer:gpu destinationOffset:0 size:bytes];
    [enc copyFromBuffer:gpu sourceOffset:0 toBuffer:dst destinationOffset:0 size:bytes];
    [enc endEncoding];
    if (!finish(cb, r)) return r;
    NSUInteger errors = 0;
    uint32_t *out = dst.contents;
    for (NSUInteger i = 0; i < bytes / 4; ++i) if (out[i] != p[i]) ++errors;
    r[@"incorrect_words"] = @(errors);
    r[@"pass"] = @(errors == 0);
    return r;
}

static id<MTLLibrary> makeLibrary(id<MTLDevice> dev, NSString *source, NSMutableDictionary *r) {
    NSError *error = nil;
    MTLCompileOptions *options = [MTLCompileOptions new];
    options.fastMathEnabled = NO;
    id<MTLLibrary> library = [dev newLibraryWithSource:source options:options error:&error];
    if (!library) r[@"error"] = error.localizedDescription ?: @"Runtime shader compilation failed";
    return library;
}

static NSMutableDictionary *computeTest(id<MTLDevice> dev) {
    NSMutableDictionary *r = [@{@"pass": @NO, @"elements": @256} mutableCopy];
    NSString *source = @"#include <metal_stdlib>\nusing namespace metal;\n"
        "kernel void transform(device const uint* a [[buffer(0)]], device uint* b [[buffer(1)]], "
        "uint i [[thread_position_in_grid]]) { if (i < 256) b[i] = a[i] * 3u + 7u; }\n";
    id<MTLLibrary> library = makeLibrary(dev, source, r);
    if (!library) return r;
    NSError *error = nil;
    id<MTLComputePipelineState> pipeline = [dev newComputePipelineStateWithFunction:[library newFunctionWithName:@"transform"] error:&error];
    if (!pipeline) { r[@"error"] = error.localizedDescription ?: @"Compute pipeline failed"; return r; }
    NSUInteger bytes = 256 * sizeof(uint32_t);
    id<MTLBuffer> src = [dev newBufferWithLength:bytes options:MTLResourceStorageModeShared];
    id<MTLBuffer> gpuIn = [dev newBufferWithLength:bytes options:MTLResourceStorageModePrivate];
    id<MTLBuffer> gpuOut = [dev newBufferWithLength:bytes options:MTLResourceStorageModePrivate];
    id<MTLBuffer> dst = [dev newBufferWithLength:bytes options:MTLResourceStorageModeShared];
    if (!src || !gpuIn || !gpuOut || !dst || !src.contents || !dst.contents) {
        r[@"error"] = @"Compute buffer allocation or mapping failed"; return r;
    }
    uint32_t *a = src.contents;
    for (NSUInteger i = 0; i < 256; ++i) a[i] = (uint32_t)(i * 7919u + 13u);
    memset(dst.contents, 0, bytes);
    id<MTLCommandQueue> queue = [dev newCommandQueue];
    id<MTLCommandBuffer> cb = [queue commandBuffer];
    id<MTLBlitCommandEncoder> blit = [cb blitCommandEncoder];
    if (!blit) { r[@"error"] = @"No input blit encoder"; return r; }
    [blit copyFromBuffer:src sourceOffset:0 toBuffer:gpuIn destinationOffset:0 size:bytes];
    [blit endEncoding];
    id<MTLComputeCommandEncoder> compute = [cb computeCommandEncoder];
    if (!compute) { r[@"error"] = @"No compute encoder"; return r; }
    [compute setComputePipelineState:pipeline];
    [compute setBuffer:gpuIn offset:0 atIndex:0];
    [compute setBuffer:gpuOut offset:0 atIndex:1];
    NSUInteger threads = MIN((NSUInteger)64, pipeline.maxTotalThreadsPerThreadgroup);
    if (!threads) { r[@"error"] = @"Invalid threadgroup capacity"; return r; }
    [compute dispatchThreadgroups:MTLSizeMake((256 + threads - 1) / threads, 1, 1)
           threadsPerThreadgroup:MTLSizeMake(threads, 1, 1)];
    [compute endEncoding];
    blit = [cb blitCommandEncoder];
    if (!blit) { r[@"error"] = @"No readback blit encoder"; return r; }
    [blit copyFromBuffer:gpuOut sourceOffset:0 toBuffer:dst destinationOffset:0 size:bytes];
    [blit endEncoding];
    if (!finish(cb, r)) return r;
    NSUInteger errors = 0;
    uint32_t *b = dst.contents;
    for (NSUInteger i = 0; i < 256; ++i) if (b[i] != a[i] * 3u + 7u) ++errors;
    r[@"incorrect_elements"] = @(errors);
    r[@"pass"] = @(errors == 0);
    return r;
}

static NSMutableDictionary *renderTest(id<MTLDevice> dev) {
    NSMutableDictionary *r = [@{@"pass": @NO, @"width": @64, @"height": @64} mutableCopy];
    NSString *source = @"#include <metal_stdlib>\nusing namespace metal;\n"
        "vertex float4 vtx(uint i [[vertex_id]]) { const float2 p[3] = {float2(-1,-1),float2(3,-1),float2(-1,3)}; return float4(p[i],0,1); }\n"
        "fragment float4 frag() { return float4(0.25,0.5,0.75,1.0); }\n";
    id<MTLLibrary> library = makeLibrary(dev, source, r);
    if (!library) return r;
    MTLRenderPipelineDescriptor *pd = [MTLRenderPipelineDescriptor new];
    pd.vertexFunction = [library newFunctionWithName:@"vtx"];
    pd.fragmentFunction = [library newFunctionWithName:@"frag"];
    pd.colorAttachments[0].pixelFormat = MTLPixelFormatRGBA8Unorm;
    NSError *error = nil;
    id<MTLRenderPipelineState> pipeline = [dev newRenderPipelineStateWithDescriptor:pd error:&error];
    if (!pipeline) { r[@"error"] = error.localizedDescription ?: @"Render pipeline failed"; return r; }
    MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:64 height:64 mipmapped:NO];
    td.storageMode = MTLStorageModePrivate;
    td.usage = MTLTextureUsageRenderTarget;
    id<MTLTexture> texture = [dev newTextureWithDescriptor:td];
    id<MTLBuffer> readback = [dev newBufferWithLength:64 * 64 * 4 options:MTLResourceStorageModeShared];
    if (!texture || !readback || !readback.contents) { r[@"error"] = @"Render target or readback allocation failed"; return r; }
    memset(readback.contents, 0, 64 * 64 * 4);
    MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor renderPassDescriptor];
    pass.colorAttachments[0].texture = texture;
    pass.colorAttachments[0].loadAction = MTLLoadActionClear;
    pass.colorAttachments[0].storeAction = MTLStoreActionStore;
    pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1);
    id<MTLCommandQueue> queue = [dev newCommandQueue];
    id<MTLCommandBuffer> cb = [queue commandBuffer];
    id<MTLRenderCommandEncoder> enc = [cb renderCommandEncoderWithDescriptor:pass];
    if (!enc) { r[@"error"] = @"No render encoder"; return r; }
    [enc setRenderPipelineState:pipeline];
    [enc setViewport:(MTLViewport){0, 0, 64, 64, 0, 1}];
    [enc drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
    [enc endEncoding];
    id<MTLBlitCommandEncoder> blit = [cb blitCommandEncoder];
    if (!blit) { r[@"error"] = @"No texture readback encoder"; return r; }
    [blit copyFromTexture:texture sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0, 0, 0)
              sourceSize:MTLSizeMake(64, 64, 1) toBuffer:readback destinationOffset:0
              destinationBytesPerRow:256 destinationBytesPerImage:64 * 256];
    [blit endEncoding];
    if (!finish(cb, r)) return r;
    const uint8_t expected[4] = {64, 128, 191, 255};
    uint8_t *pixels = readback.contents;
    NSMutableArray *first = [NSMutableArray new];
    for (NSUInteger i = 0; i < 32; ++i) [first addObject:@(pixels[i])];
    r[@"first_pixels"] = first;
    NSUInteger errors = 0;
    for (NSUInteger i = 0; i < 64 * 64; ++i) {
        BOOL bad = NO;
        for (NSUInteger c = 0; c < 4; ++c) {
            int difference = (int)pixels[i * 4 + c] - (int)expected[c];
            if (difference < -1 || difference > 1) bad = YES;
        }
        if (bad) ++errors;
    }
    r[@"incorrect_pixels"] = @(errors);
    r[@"pass"] = @(errors == 0);
    return r;
}

int main(void) {
    @autoreleasepool {
        NSMutableDictionary *report = [NSMutableDictionary new];
        NSMutableArray *enumerated = [NSMutableArray new];
        id<MTLDevice> selected = nil;
        for (id<MTLDevice> dev in MTLCopyAllDevices()) {
            [enumerated addObject:@{@"name": dev.name ?: @"", @"registry_id": @(dev.registryID),
                @"max_buffer_length": @(dev.maxBufferLength), @"recommended_working_set": @(dev.recommendedMaxWorkingSetSize)}];
            NSString *lower = [dev.name lowercaseString];
            if ([lower containsString:@"nvidia"] || [lower containsString:@"geforce"] || [lower containsString:@"rtx"]) selected = dev;
        }
        report[@"devices"] = enumerated;
        report[@"all_gpu_tests_pass"] = @NO;
        if (!selected) report[@"error"] = @"No NVIDIA Metal device; no GPU tests were executed";
        else {
            report[@"selected_device"] = selected.name;
            report[@"selected_registry_id"] = @(selected.registryID);
            @try { report[@"copy"] = copyTest(selected); }
            @catch (NSException *e) { report[@"copy"] = @{@"pass": @NO, @"exception": e.reason ?: @""}; }
            @try { report[@"compute"] = computeTest(selected); }
            @catch (NSException *e) { report[@"compute"] = @{@"pass": @NO, @"exception": e.reason ?: @""}; }
            @try { report[@"render"] = renderTest(selected); }
            @catch (NSException *e) { report[@"render"] = @{@"pass": @NO, @"exception": e.reason ?: @""}; }
            report[@"all_gpu_tests_pass"] = @([report[@"copy"][@"pass"] boolValue] &&
                [report[@"compute"][@"pass"] boolValue] && [report[@"render"][@"pass"] boolValue]);
        }
        report[@"scope"] = @"Small buffer copy, runtime-compiled compute, and 64x64 shader rendering only; no large-allocation, application, display or stability qualification";
        NSData *json = [NSJSONSerialization dataWithJSONObject:report options:0 error:nil];
        fwrite(json.bytes, 1, json.length, stdout);
        fputc('\n', stdout);
        return [report[@"all_gpu_tests_pass"] boolValue] ? 0 : 2;
    }
}
