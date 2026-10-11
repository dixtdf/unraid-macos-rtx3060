/*
 * Small correctness probe for the NullMoth OpenCL implementation.
 * macOS: clang -std=c11 -O2 -Wall -Wextra -Wno-deprecated-declarations \
 *          tests/native/opencl-acceptance.c -framework OpenCL -o opencl-acceptance
 * Run:   ./opencl-acceptance
 *
 * This is not a conformance suite, a benchmark, or an OpenCL feature claim.
 * API and barrier semantics: https://registry.khronos.org/OpenCL/specs/
 * The integer tree reduction on the device is checked against a linear host
 * sum. Nonuniform inputs and multiple work-groups expose indexing mistakes.
 */
#define CL_SILENCE_DEPRECATION
#define CL_TARGET_OPENCL_VERSION 120
#ifdef __APPLE__
#include <OpenCL/opencl.h>
#else
#include <CL/cl.h>
#endif
#include <ctype.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

enum { VECTOR_COUNT = 1009, LOCAL_SIZE = 64, GROUP_COUNT = 17,
       REDUCTION_COUNT = LOCAL_SIZE * GROUP_COUNT, TEXT_SIZE = 1024 };

static const char kernels[] =
    "__kernel void array_transform(__global const float *a,"
    " __global const float *b, __global float *out, uint n) {"
    " size_t i = get_global_id(0);"
    " if (i < n) out[i] = a[i] * 3.0f + b[i] * 0.5f - 7.0f;"
    "}\n"
    "__kernel void local_reduce(__global const int *in,"
    " __global int *out, __local int *scratch) {"
    " size_t i = get_global_id(0), lane = get_local_id(0);"
    " scratch[lane] = in[i];"
    " barrier(CLK_LOCAL_MEM_FENCE);"
    " for (size_t step = get_local_size(0) / 2; step > 0; step >>= 1) {"
    "   if (lane < step) scratch[lane] += scratch[lane + step];"
    "   barrier(CLK_LOCAL_MEM_FENCE);"
    " }"
    " if (lane == 0) out[get_group_id(0)] = scratch[0];"
    "}\n";

static void json_string(const char *s)
{
    const unsigned char *p = (const unsigned char *)s;
    putchar('"');
    while (*p) {
        unsigned char ch = *p++;
        if (ch == '"' || ch == '\\') printf("\\%c", ch);
        else if (ch < 0x20) printf("\\u%04x", ch);
        else putchar(ch);
    }
    putchar('"');
}

static int contains_ascii(const char *text, const char *needle)
{
    size_t n = strlen(needle);
    for (; *text; ++text) {
        size_t i = 0;
        while (i < n && text[i] &&
               tolower((unsigned char)text[i]) ==
               tolower((unsigned char)needle[i])) ++i;
        if (i == n) return 1;
    }
    return 0;
}

static cl_int device_text(cl_device_id device, cl_device_info field,
                          char out[TEXT_SIZE])
{
    size_t size = 0;
    cl_int err = clGetDeviceInfo(device, field, 0, NULL, &size);
    if (err != CL_SUCCESS) return err;
    if (size == 0 || size > TEXT_SIZE) return CL_INVALID_VALUE;
    err = clGetDeviceInfo(device, field, TEXT_SIZE, out, NULL);
    out[TEXT_SIZE - 1] = '\0';
    return err;
}

int main(void)
{
    cl_platform_id *platforms = NULL;
    cl_device_id *devices = NULL, selected = NULL;
    cl_context context = NULL;
    cl_command_queue queue = NULL;
    cl_program program = NULL;
    cl_kernel vector_kernel = NULL, reduction_kernel = NULL;
    cl_mem a_mem = NULL, b_mem = NULL, vector_mem = NULL;
    cl_mem reduction_in_mem = NULL, reduction_out_mem = NULL;
    cl_uint platform_count = 0, gpu_count = 0, nvidia_count = 0;
    cl_uint vendor_id = 0;
    char name[TEXT_SIZE] = "", vendor[TEXT_SIZE] = "";
    char device_version[TEXT_SIZE] = "", c_version[TEXT_SIZE] = "";
    char build_log[4096] = "";
    const char *stage = "enumerate_platforms";
    const char *message = "";
    cl_int err = CL_SUCCESS;
    int vector_ran = 0, reduction_ran = 0, passed = 0;
    size_t vector_mismatches = 0, reduction_mismatches = 0;
    float a[VECTOR_COUNT], b[VECTOR_COUNT], vector_out[VECTOR_COUNT];
    cl_int reduction_in[REDUCTION_COUNT], reduction_out[GROUP_COUNT];
    size_t max_work_group = 0, kernel_work_group = 0;
    size_t *max_work_items = NULL;
    cl_uint dimensions = 0;
    cl_ulong local_memory = 0, kernel_local_memory = 0;

#define REQUIRE_OK(call) do { err = (call); if (err != CL_SUCCESS) \
    { message = #call; goto cleanup; } } while (0)
#define REQUIRE_HANDLE(handle) do { if (!(handle) || err != CL_SUCCESS) \
    { if (err == CL_SUCCESS) err = CL_OUT_OF_RESOURCES; \
      message = #handle; goto cleanup; } } while (0)

    err = clGetPlatformIDs(0, NULL, &platform_count);
    if (err != CL_SUCCESS) {
        message = "OpenCL unavailable: clGetPlatformIDs failed"; goto cleanup;
    }
    if (platform_count == 0 || platform_count > 128) {
        message = "no platforms, or platform count exceeds probe limit";
        goto cleanup;
    }
    platforms = calloc(platform_count, sizeof(*platforms));
    if (!platforms) { message = "platform allocation failed"; goto cleanup; }
    REQUIRE_OK(clGetPlatformIDs(platform_count, platforms, NULL));
    stage = "enumerate_nvidia_gpu";
    for (cl_uint p = 0; p < platform_count; ++p) {
        cl_uint count = 0;
        err = clGetDeviceIDs(platforms[p], CL_DEVICE_TYPE_GPU, 0, NULL, &count);
        if (err == CL_DEVICE_NOT_FOUND) { err = CL_SUCCESS; continue; }
        if (err != CL_SUCCESS) { message = "clGetDeviceIDs count"; goto cleanup; }
        if (count == 0 || count > 4096 || gpu_count > 4096 - count) {
            message = "GPU count outside probe limit"; goto cleanup;
        }
        devices = calloc(count, sizeof(*devices));
        if (!devices) { message = "device allocation failed"; goto cleanup; }
        REQUIRE_OK(clGetDeviceIDs(platforms[p], CL_DEVICE_TYPE_GPU,
                                 count, devices, NULL));
        gpu_count += count;
        for (cl_uint d = 0; d < count; ++d) {
            char candidate_name[TEXT_SIZE] = "", candidate_vendor[TEXT_SIZE] = "";
            cl_uint candidate_id = 0;
            REQUIRE_OK(device_text(devices[d], CL_DEVICE_NAME, candidate_name));
            REQUIRE_OK(device_text(devices[d], CL_DEVICE_VENDOR, candidate_vendor));
            REQUIRE_OK(clGetDeviceInfo(devices[d], CL_DEVICE_VENDOR_ID,
                                      sizeof(candidate_id), &candidate_id, NULL));
            if (candidate_id == 0x10de || contains_ascii(candidate_vendor, "nvidia") ||
                contains_ascii(candidate_name, "nvidia") ||
                contains_ascii(candidate_name, "geforce")) {
                ++nvidia_count;
                if (!selected) {
                    selected = devices[d]; vendor_id = candidate_id;
                    memcpy(name, candidate_name, sizeof(name));
                    memcpy(vendor, candidate_vendor, sizeof(vendor));
                }
            }
        }
        free(devices); devices = NULL;
    }
    if (!selected) { message = "no NVIDIA GPU exposed by OpenCL"; goto cleanup; }
    stage = "device_limits";
    REQUIRE_OK(device_text(selected, CL_DEVICE_VERSION, device_version));
    REQUIRE_OK(device_text(selected, CL_DEVICE_OPENCL_C_VERSION, c_version));
    REQUIRE_OK(clGetDeviceInfo(selected, CL_DEVICE_MAX_WORK_GROUP_SIZE,
                              sizeof(max_work_group), &max_work_group, NULL));
    REQUIRE_OK(clGetDeviceInfo(selected, CL_DEVICE_MAX_WORK_ITEM_DIMENSIONS,
                              sizeof(dimensions), &dimensions, NULL));
    REQUIRE_OK(clGetDeviceInfo(selected, CL_DEVICE_LOCAL_MEM_SIZE,
                              sizeof(local_memory), &local_memory, NULL));
    if (dimensions == 0 || dimensions > 32) {
        message = "work-item dimensions outside probe limit"; goto cleanup;
    }
    max_work_items = calloc(dimensions, sizeof(*max_work_items));
    if (!max_work_items) { message = "dimension allocation failed"; goto cleanup; }
    REQUIRE_OK(clGetDeviceInfo(selected, CL_DEVICE_MAX_WORK_ITEM_SIZES,
                              dimensions * sizeof(*max_work_items), max_work_items, NULL));
    if (max_work_group < LOCAL_SIZE || max_work_items[0] < LOCAL_SIZE ||
        local_memory < LOCAL_SIZE * sizeof(cl_int)) {
        message = "device cannot run the fixed 64-lane local-memory probe"; goto cleanup;
    }
    stage = "create_context_queue";
    context = clCreateContext(NULL, 1, &selected, NULL, NULL, &err);
    REQUIRE_HANDLE(context);
    queue = clCreateCommandQueue(context, selected, 0, &err);
    REQUIRE_HANDLE(queue);
    stage = "build_kernels";
    const char *source = kernels;
    program = clCreateProgramWithSource(context, 1, &source, NULL, &err);
    REQUIRE_HANDLE(program);
    err = clBuildProgram(program, 1, &selected, "-cl-std=CL1.2", NULL, NULL);
    if (err != CL_SUCCESS) {
        size_t log_size = 0;
        if (clGetProgramBuildInfo(program, selected, CL_PROGRAM_BUILD_LOG,
                                 0, NULL, &log_size) == CL_SUCCESS && log_size > 0) {
            if (log_size <= sizeof(build_log)) {
                (void)clGetProgramBuildInfo(program, selected, CL_PROGRAM_BUILD_LOG,
                                           sizeof(build_log), build_log, NULL);
                build_log[sizeof(build_log) - 1] = '\0';
            } else strcpy(build_log, "build log exceeds 4096-byte probe limit");
        }
        message = "clBuildProgram failed"; goto cleanup;
    }
    vector_kernel = clCreateKernel(program, "array_transform", &err);
    REQUIRE_HANDLE(vector_kernel);
    reduction_kernel = clCreateKernel(program, "local_reduce", &err);
    REQUIRE_HANDLE(reduction_kernel);
    REQUIRE_OK(clGetKernelWorkGroupInfo(reduction_kernel, selected,
                                       CL_KERNEL_WORK_GROUP_SIZE,
                                       sizeof(kernel_work_group), &kernel_work_group, NULL));
    if (kernel_work_group < LOCAL_SIZE) {
        message = "compiled reduction kernel cannot use 64 work-items"; goto cleanup;
    }
    stage = "create_buffers";
    for (size_t i = 0; i < VECTOR_COUNT; ++i) {
        a[i] = ((int)((i * 37 + 11) % 251) - 125) * 0.25f;
        b[i] = ((int)((i * 19 + 3) % 127) - 63) * 0.5f;
        vector_out[i] = 123456.0f;
    }
    for (size_t i = 0; i < REDUCTION_COUNT; ++i)
        reduction_in[i] = (cl_int)((int)((i * 17 + 11) % 101) - 50 +
                                    ((int)(i % 7) - 3) * 9);
    for (size_t g = 0; g < GROUP_COUNT; ++g) reduction_out[g] = 123456;
    a_mem = clCreateBuffer(context, CL_MEM_READ_ONLY | CL_MEM_COPY_HOST_PTR,
                           sizeof(a), a, &err); REQUIRE_HANDLE(a_mem);
    b_mem = clCreateBuffer(context, CL_MEM_READ_ONLY | CL_MEM_COPY_HOST_PTR,
                           sizeof(b), b, &err); REQUIRE_HANDLE(b_mem);
    vector_mem = clCreateBuffer(context, CL_MEM_READ_WRITE | CL_MEM_COPY_HOST_PTR,
                                sizeof(vector_out), vector_out, &err);
    REQUIRE_HANDLE(vector_mem);
    reduction_in_mem = clCreateBuffer(context, CL_MEM_READ_ONLY | CL_MEM_COPY_HOST_PTR,
                                      sizeof(reduction_in), reduction_in, &err);
    REQUIRE_HANDLE(reduction_in_mem);
    reduction_out_mem = clCreateBuffer(context, CL_MEM_READ_WRITE | CL_MEM_COPY_HOST_PTR,
                                       sizeof(reduction_out), reduction_out, &err);
    REQUIRE_HANDLE(reduction_out_mem);
    stage = "array_transform";
    cl_uint n = VECTOR_COUNT;
    REQUIRE_OK(clSetKernelArg(vector_kernel, 0, sizeof(a_mem), &a_mem));
    REQUIRE_OK(clSetKernelArg(vector_kernel, 1, sizeof(b_mem), &b_mem));
    REQUIRE_OK(clSetKernelArg(vector_kernel, 2, sizeof(vector_mem), &vector_mem));
    REQUIRE_OK(clSetKernelArg(vector_kernel, 3, sizeof(n), &n));
    size_t vector_global = VECTOR_COUNT;
    REQUIRE_OK(clEnqueueNDRangeKernel(queue, vector_kernel, 1, NULL,
                                     &vector_global, NULL, 0, NULL, NULL));
    REQUIRE_OK(clEnqueueReadBuffer(queue, vector_mem, CL_TRUE, 0, sizeof(vector_out),
                                  vector_out, 0, NULL, NULL));
    vector_ran = 1;
    for (size_t i = 0; i < VECTOR_COUNT; ++i) {
        /* Inputs and results are exactly representable binary fractions. */
        float expected = (a[i] + a[i] + a[i]) + b[i] / 2.0f - 7.0f;
        if (vector_out[i] != expected) ++vector_mismatches;
    }
    stage = "local_memory_barrier_reduction";
    REQUIRE_OK(clSetKernelArg(reduction_kernel, 0, sizeof(reduction_in_mem),
                             &reduction_in_mem));
    REQUIRE_OK(clSetKernelArg(reduction_kernel, 1, sizeof(reduction_out_mem),
                             &reduction_out_mem));
    REQUIRE_OK(clSetKernelArg(reduction_kernel, 2, LOCAL_SIZE * sizeof(cl_int), NULL));
    REQUIRE_OK(clGetKernelWorkGroupInfo(reduction_kernel, selected,
                                       CL_KERNEL_LOCAL_MEM_SIZE,
                                       sizeof(kernel_local_memory), &kernel_local_memory, NULL));
    if (kernel_local_memory > local_memory) {
        message = "kernel local allocation exceeds device limit"; goto cleanup;
    }
    size_t reduction_global = REDUCTION_COUNT, reduction_local = LOCAL_SIZE;
    REQUIRE_OK(clEnqueueNDRangeKernel(queue, reduction_kernel, 1, NULL,
                                     &reduction_global, &reduction_local, 0, NULL, NULL));
    REQUIRE_OK(clEnqueueReadBuffer(queue, reduction_out_mem, CL_TRUE, 0,
                                  sizeof(reduction_out), reduction_out, 0, NULL, NULL));
    reduction_ran = 1;
    for (size_t g = 0; g < GROUP_COUNT; ++g) {
        int64_t expected = 0;
        for (size_t i = g * LOCAL_SIZE; i < (g + 1) * LOCAL_SIZE; ++i)
            expected += reduction_in[i];
        if ((int64_t)reduction_out[g] != expected) ++reduction_mismatches;
    }
    REQUIRE_OK(clFinish(queue));
    passed = vector_mismatches == 0 && reduction_mismatches == 0;
    stage = "complete";
    if (!passed) message = "computed array contents differ from host reference";

cleanup:
    printf("{\"schema\":\"nullmoth.opencl.acceptance.v1\",\"pass\":%s,",
           passed ? "true" : "false");
    printf("\"platforms\":%u,\"gpu_devices\":%u,\"nvidia_gpu_devices\":%u,",
           platform_count, gpu_count, nvidia_count);
    printf("\"device\":{\"name\":"); json_string(name);
    printf(",\"vendor\":"); json_string(vendor);
    printf(",\"vendor_id\":%u,\"version\":", vendor_id); json_string(device_version);
    printf(",\"opencl_c_version\":"); json_string(c_version); printf("},");
    printf("\"array_transform\":{\"ran\":%s,\"pass\":%s,\"elements\":%u,"
           "\"mismatches\":%zu},", vector_ran ? "true" : "false",
           vector_ran && vector_mismatches == 0 ? "true" : "false",
           (unsigned)VECTOR_COUNT, vector_mismatches);
    printf("\"local_memory_barrier_reduction\":{\"ran\":%s,\"pass\":%s,"
           "\"work_group_size\":%u,\"groups\":%u,\"elements\":%u,\"mismatches\":%zu},",
           reduction_ran ? "true" : "false",
           reduction_ran && reduction_mismatches == 0 ? "true" : "false",
           (unsigned)LOCAL_SIZE, (unsigned)GROUP_COUNT, (unsigned)REDUCTION_COUNT,
           reduction_mismatches);
    printf("\"stage\":"); json_string(stage);
    printf(",\"opencl_error\":%d,\"message\":", (int)err); json_string(message);
    printf(",\"build_log\":"); json_string(build_log); printf("}\n");
    if (queue) (void)clFinish(queue);
    if (reduction_out_mem) (void)clReleaseMemObject(reduction_out_mem);
    if (reduction_in_mem) (void)clReleaseMemObject(reduction_in_mem);
    if (vector_mem) (void)clReleaseMemObject(vector_mem);
    if (b_mem) (void)clReleaseMemObject(b_mem);
    if (a_mem) (void)clReleaseMemObject(a_mem);
    if (reduction_kernel) (void)clReleaseKernel(reduction_kernel);
    if (vector_kernel) (void)clReleaseKernel(vector_kernel);
    if (program) (void)clReleaseProgram(program);
    if (queue) (void)clReleaseCommandQueue(queue);
    if (context) (void)clReleaseContext(context);
    free(max_work_items);
    free(devices);
    free(platforms);
    return passed ? EXIT_SUCCESS : EXIT_FAILURE;
}
