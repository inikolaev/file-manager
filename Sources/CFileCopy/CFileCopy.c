#include "CFileCopy.h"
#include <sys/types.h>
#include <copyfile.h>
#include <errno.h>

struct progress_context {
    commander_copy_progress progress;
    void *context;
};

static int report_progress(int what, int stage, copyfile_state_t state,
                           const char *source, const char *destination, void *raw) {
    (void)what; (void)stage; (void)source; (void)destination;
    struct progress_context *context = raw;
    off_t copied = 0;
    copyfile_state_get(state, COPYFILE_STATE_COPIED, &copied);
    return context->progress(copied, context->context) ? COPYFILE_QUIT : COPYFILE_CONTINUE;
}

int commander_copy_file(const char *source, const char *destination,
                        commander_copy_progress progress, void *context) {
    copyfile_state_t state = copyfile_state_alloc();
    if (!state) return ENOMEM;
    struct progress_context wrapper = { progress, context };
    if (copyfile_state_set(state, COPYFILE_STATE_STATUS_CB, report_progress) < 0 ||
        copyfile_state_set(state, COPYFILE_STATE_STATUS_CTX, &wrapper) < 0) {
        int error = errno;
        copyfile_state_free(state);
        return error;
    }
    int result = copyfile(source, destination, state,
                          COPYFILE_ALL | COPYFILE_EXCL | COPYFILE_NOFOLLOW_SRC);
    int error = result < 0 ? errno : 0;
    copyfile_state_free(state);
    return error;
}
