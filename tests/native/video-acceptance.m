#import <Foundation/Foundation.h>
#import <VideoToolbox/VideoToolbox.h>
#import <CoreVideo/CoreVideo.h>
#import <CoreMedia/CoreMedia.h>

typedef struct {
    CFMutableArrayRef samples;
    int callbacks, errors;
    size_t bytes;
} EncodeState;
typedef struct { int frames, errors; double lumaError, chromaError; size_t checkedPixels, checkedChromaSamples; OSType pixelFormat; int firstLuma; } DecodeState;

static void encodeCallback(void *ref, void *source, OSStatus status,
                           VTEncodeInfoFlags flags, CMSampleBufferRef sample) {
    EncodeState *s = ref;
    if (status || !sample || !CMSampleBufferDataIsReady(sample)) { s->errors++; return; }
    s->callbacks++;
    s->bytes += CMSampleBufferGetTotalSampleSize(sample);
    CFArrayAppendValue(s->samples, sample);
}
static void decodeCallback(void *ref, void *source, OSStatus status,
                           VTDecodeInfoFlags flags, CVImageBufferRef image,
                           CMTime presentationTimeStamp, CMTime presentationDuration) {
    DecodeState *s = ref;
    if (status || !image) { s->errors++; return; }
    s->frames++;
    int frame = CMTIME_IS_NUMERIC(presentationTimeStamp) ? (int)CMTimeConvertScale(presentationTimeStamp,30,kCMTimeRoundingMethod_RoundHalfAwayFromZero).value : -1;
    s->pixelFormat = CVPixelBufferGetPixelFormatType(image);
    CVPixelBufferLockBaseAddress(image, kCVPixelBufferLock_ReadOnly);
    BOOL tenBit = s->pixelFormat == kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange || s->pixelFormat == kCVPixelFormatType_420YpCbCr10BiPlanarFullRange;
    BOOL eightBit = s->pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange || s->pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange;
    if (frame < 0 || !CVPixelBufferIsPlanar(image) || (!tenBit && !eightBit)) { s->errors++; }
    else {
        const uint8_t *y = CVPixelBufferGetBaseAddressOfPlane(image, 0);
        size_t stride = CVPixelBufferGetBytesPerRowOfPlane(image, 0);
        for (size_t row=0; row<CVPixelBufferGetHeightOfPlane(image,0); row+=16)
            for (size_t col=0; col<CVPixelBufferGetWidthOfPlane(image,0); col+=16) {
                int expected = 16 + ((col+row+frame*7)%220);
                int actual = tenBit ? (((const uint16_t *)(y+row*stride))[col] >> 8) : y[row*stride+col];
                if (frame==0 && row==0 && col==0) s->firstLuma=actual;
                s->lumaError += abs(actual - expected);
                s->checkedPixels++;
            }
        const uint8_t *uv = CVPixelBufferGetBaseAddressOfPlane(image,1);
        size_t uvStride = CVPixelBufferGetBytesPerRowOfPlane(image,1);
        for (size_t row=0;row<CVPixelBufferGetHeightOfPlane(image,1);row+=8)
            for (size_t col=0;col<CVPixelBufferGetWidthOfPlane(image,1);col+=8) {
                int u=tenBit ? (((const uint16_t *)(uv+row*uvStride))[col*2]>>8) : uv[row*uvStride+col*2];
                int v=tenBit ? (((const uint16_t *)(uv+row*uvStride))[col*2+1]>>8) : uv[row*uvStride+col*2+1];
                int expectedU=64+(int)((col+frame*3)%128), expectedV=64+(int)((row+frame*2)%128);
                s->chromaError += abs(u-expectedU) + abs(v-expectedV);
                s->checkedChromaSamples+=2;
            }
    }
    CVPixelBufferUnlockBaseAddress(image, kCVPixelBufferLock_ReadOnly);
}
static id copyProperty(VTSessionRef session, CFStringRef key) {
    CFTypeRef value = NULL;
    OSStatus status = VTSessionCopyProperty(session, key, kCFAllocatorDefault, &value);
    if (status || !value) return [NSNull null];
    return CFBridgingRelease(value);
}
static NSDictionary *decodeSamples(CFArrayRef samples, BOOL strict) {
    if (!CFArrayGetCount(samples)) return @{ @"skipped": @"no_encoded_samples" };
    CMSampleBufferRef first = (CMSampleBufferRef)CFArrayGetValueAtIndex(samples, 0);
    NSDictionary *spec = strict ? @{(__bridge NSString *)kVTVideoDecoderSpecification_RequireHardwareAcceleratedVideoDecoder:@YES} : @{(__bridge NSString *)kVTVideoDecoderSpecification_EnableHardwareAcceleratedVideoDecoder:@NO};
    NSDictionary *attrs = @{(__bridge NSString *)kCVPixelBufferPixelFormatTypeKey:@(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)};
    DecodeState state = {0};
    VTDecompressionOutputCallbackRecord cb = {decodeCallback, &state};
    VTDecompressionSessionRef session = NULL;
    OSStatus created = VTDecompressionSessionCreate(kCFAllocatorDefault,
        CMSampleBufferGetFormatDescription(first), (__bridge CFDictionaryRef)spec,
        (__bridge CFDictionaryRef)attrs, &cb, &session);
    NSMutableDictionary *r = [@{@"require_hardware":@(strict), @"create_status":@(created)} mutableCopy];
    if (created || !session) return r;
    r[@"using_hardware"] = copyProperty(session, kVTDecompressionPropertyKey_UsingHardwareAcceleratedVideoDecoder);
    OSStatus frameStatus = noErr;
    for (CFIndex i=0; i<CFArrayGetCount(samples); i++) {
        CMSampleBufferRef sample = (CMSampleBufferRef)CFArrayGetValueAtIndex(samples, i);
        VTDecodeInfoFlags flags = 0;
        OSStatus s = VTDecompressionSessionDecodeFrame(session, sample, 0, (void *)(intptr_t)(i+1), &flags);
        if (s && !frameStatus) frameStatus = s;
    }
    OSStatus finish = VTDecompressionSessionFinishDelayedFrames(session);
    OSStatus wait = VTDecompressionSessionWaitForAsynchronousFrames(session);
    r[@"decode_status"] = @(frameStatus);
    r[@"finish_status"] = @(finish);
    r[@"wait_status"] = @(wait);
    r[@"decoded_frames"] = @(state.frames);
    r[@"callback_errors"] = @(state.errors);
    double meanError = state.checkedPixels ? state.lumaError/state.checkedPixels : 999;
    double meanChromaError = state.checkedChromaSamples ? state.chromaError/state.checkedChromaSamples : 999;
    r[@"checked_luma_pixels"] = @(state.checkedPixels);
    char fourcc[5] = {(char)(state.pixelFormat>>24),(char)(state.pixelFormat>>16),(char)(state.pixelFormat>>8),(char)state.pixelFormat,0};
    r[@"decoded_pixel_format"] = [NSString stringWithUTF8String:fourcc] ?: @"unknown";
    r[@"first_frame_first_luma"] = @(state.firstLuma);
    r[@"mean_absolute_luma_error"] = @(meanError);
    r[@"checked_chroma_samples"] = @(state.checkedChromaSamples);
    r[@"mean_absolute_chroma_error"] = @(meanChromaError);
    r[@"content_pass"] = @(meanError < 12 && meanChromaError < 12);
    r[@"pass"] = @(!frameStatus && !finish && !wait && !state.errors && state.frames == CFArrayGetCount(samples) && meanError < 12 && meanChromaError < 12);
    VTDecompressionSessionInvalidate(session); CFRelease(session);
    return r;
}
static NSDictionary *encodeVideo(CMVideoCodecType codec, BOOL strict) {
    const int width=1280, height=720, frames=30;
    NSDictionary *spec = strict ? @{(__bridge NSString *)kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder:@YES} : @{
        (__bridge NSString *)kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder:@NO,
        (__bridge NSString *)kVTVideoEncoderSpecification_EncoderID:codec==kCMVideoCodecType_H264 ? @"com.apple.videotoolbox.videoencoder.h264" : @"com.apple.videotoolbox.videoencoder.hevc.vcp"
    };
    NSDictionary *attrs = @{
        (__bridge NSString *)kCVPixelBufferPixelFormatTypeKey:@(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange),
        (__bridge NSString *)kCVPixelBufferWidthKey:@(width),
        (__bridge NSString *)kCVPixelBufferHeightKey:@(height),
        (__bridge NSString *)kCVPixelBufferIOSurfacePropertiesKey:@{}
    };
    EncodeState state = {0};
    state.samples = CFArrayCreateMutable(kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks);
    VTCompressionSessionRef session = NULL;
    OSStatus created = VTCompressionSessionCreate(kCFAllocatorDefault, width, height, codec,
        (__bridge CFDictionaryRef)spec, (__bridge CFDictionaryRef)attrs, NULL,
        encodeCallback, &state, &session);
    NSMutableDictionary *r = [@{@"require_hardware":@(strict), @"create_status":@(created),
        @"width":@(width), @"height":@(height), @"submitted_frames":@(frames)} mutableCopy];
    if (created || !session) { CFRelease(state.samples); return r; }
    CFDictionaryRef sessionProperties = NULL, globalProperties = NULL;
    CFStringRef globalEncoderID = NULL;
    OSStatus sessionPropertyStatus = VTSessionCopySupportedPropertyDictionary(session, &sessionProperties);
    OSStatus globalPropertyStatus = VTCopySupportedPropertyDictionaryForEncoder(width,height,codec,(__bridge CFDictionaryRef)spec,&globalEncoderID,&globalProperties);
    r[@"session_property_query_status"] = @(sessionPropertyStatus);
    r[@"session_property_count"] = @(sessionProperties ? CFDictionaryGetCount(sessionProperties) : 0);
    r[@"global_property_query_status"] = @(globalPropertyStatus);
    r[@"global_property_count"] = @(globalProperties ? CFDictionaryGetCount(globalProperties) : 0);
    r[@"global_property_encoder_id"] = globalEncoderID ? (__bridge NSString *)globalEncoderID : [NSNull null];
    if (sessionProperties) CFRelease(sessionProperties);
    if (globalProperties) CFRelease(globalProperties);
    if (globalEncoderID) CFRelease(globalEncoderID);
    VTSessionSetProperty(session, kVTCompressionPropertyKey_RealTime, kCFBooleanTrue);
    VTSessionSetProperty(session, kVTCompressionPropertyKey_AllowFrameReordering, kCFBooleanFalse);
    NSNumber *bitrate=@2000000, *fps=@30;
    VTSessionSetProperty(session, kVTCompressionPropertyKey_AverageBitRate, (__bridge CFTypeRef)bitrate);
    VTSessionSetProperty(session, kVTCompressionPropertyKey_ExpectedFrameRate, (__bridge CFTypeRef)fps);
    OSStatus prepared = VTCompressionSessionPrepareToEncodeFrames(session);
    r[@"prepare_status"] = @(prepared);
    r[@"using_hardware"] = copyProperty(session, kVTCompressionPropertyKey_UsingHardwareAcceleratedVideoEncoder);
    r[@"encoder_id"] = copyProperty(session, kVTCompressionPropertyKey_EncoderID);
    OSStatus encodeStatus = prepared;
    CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
    if (!prepared) for (int i=0; i<frames; i++) {
        CVPixelBufferRef pixel = NULL;
        OSStatus s = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault,
            VTCompressionSessionGetPixelBufferPool(session), &pixel);
        if (s || !pixel) { encodeStatus = s ? s : -1; break; }
        CVPixelBufferLockBaseAddress(pixel, 0);
        uint8_t *y = CVPixelBufferGetBaseAddressOfPlane(pixel, 0);
        size_t ys = CVPixelBufferGetBytesPerRowOfPlane(pixel, 0);
        for (int row=0; row<height; row++) for (int col=0; col<width; col++)
            y[row*ys+col] = 16 + ((col+row+i*7)%220);
        uint8_t *uv = CVPixelBufferGetBaseAddressOfPlane(pixel, 1);
        size_t uvStride=CVPixelBufferGetBytesPerRowOfPlane(pixel,1);
        for (size_t row=0;row<CVPixelBufferGetHeightOfPlane(pixel,1);row++)
            for (size_t col=0;col<CVPixelBufferGetWidthOfPlane(pixel,1);col++) {
                uv[row*uvStride+col*2]=64+((col+i*3)%128);
                uv[row*uvStride+col*2+1]=64+((row+i*2)%128);
            }
        CVPixelBufferUnlockBaseAddress(pixel, 0);
        VTEncodeInfoFlags flags=0;
        s = VTCompressionSessionEncodeFrame(session, pixel, CMTimeMake(i, 30), CMTimeMake(1, 30), NULL, NULL, &flags);
        CFRelease(pixel);
        if (s && !encodeStatus) encodeStatus=s;
    }
    OSStatus completed = VTCompressionSessionCompleteFrames(session, kCMTimeInvalid);
    r[@"encode_status"] = @(encodeStatus); r[@"complete_status"] = @(completed);
    r[@"encoded_frames"] = @(state.callbacks); r[@"callback_errors"] = @(state.errors);
    r[@"encoded_bytes"] = @(state.bytes);
    r[@"elapsed_seconds"] = @(CFAbsoluteTimeGetCurrent()-start);
    r[@"using_hardware"] = copyProperty(session, kVTCompressionPropertyKey_UsingHardwareAcceleratedVideoEncoder);
    BOOL apiPass=!encodeStatus && !completed && !state.errors && state.callbacks==frames;
    r[@"encode_api_pass"] = @(apiPass);
    VTCompressionSessionInvalidate(session); CFRelease(session);
    if (CFArrayGetCount(state.samples)) {
        r[@"hardware_decode"] = decodeSamples(state.samples, YES);
        r[@"software_decode"] = decodeSamples(state.samples, NO);
    }
    r[@"pass"] = @(apiPass && [r[@"hardware_decode"][@"pass"] boolValue] && [r[@"software_decode"][@"pass"] boolValue]);
    CFRelease(state.samples);
    return r;
}
int main(void) {
    @autoreleasepool {
        CFArrayRef rawList=NULL;
        OSStatus listStatus=VTCopyVideoEncoderList(NULL, &rawList);
        NSMutableArray *encoders=[NSMutableArray array];
        if (rawList) {
            for (NSDictionary *item in (__bridge NSArray *)rawList) {
                NSNumber *codec=item[(__bridge NSString *)kVTVideoEncoderList_CodecType];
                if (codec.unsignedIntValue!=kCMVideoCodecType_H264 && codec.unsignedIntValue!=kCMVideoCodecType_HEVC) continue;
                [encoders addObject:@{
                    @"codec":codec.unsignedIntValue==kCMVideoCodecType_H264 ? @"H264" : @"HEVC",
                    @"encoder_id":item[(__bridge NSString *)kVTVideoEncoderList_EncoderID] ?: [NSNull null],
                    @"name":item[(__bridge NSString *)kVTVideoEncoderList_EncoderName] ?: [NSNull null],
                    @"hardware":item[(__bridge NSString *)kVTVideoEncoderList_IsHardwareAccelerated] ?: [NSNull null]
                }];
            }
            CFRelease(rawList);
        }
        NSMutableDictionary *report=[@{@"encoder_list_status":@(listStatus),@"encoders":encoders,
            @"os_version":[NSProcessInfo processInfo].operatingSystemVersionString} mutableCopy];
        CMVideoCodecType codecs[]={kCMVideoCodecType_H264,kCMVideoCodecType_HEVC};
        NSArray *names=@[@"H264",@"HEVC"];
        for(int i=0;i<2;i++) report[names[i]]=@{
            @"hardware_decode_supported":@(VTIsHardwareDecodeSupported(codecs[i])),
            @"hardware_encode":encodeVideo(codecs[i],YES),
            @"software_encode":encodeVideo(codecs[i],NO)
        };
        NSError *error=nil;
        NSData *json=[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:&error];
        if(!json) { fprintf(stderr,"JSON error: %s\n",error.description.UTF8String); return 2; }
        fwrite(json.bytes,1,json.length,stdout); fputc('\n',stdout);
    }
    return 0;
}
