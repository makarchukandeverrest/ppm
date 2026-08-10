export function reduceErrors(error) {
    if (!error) {
        return 'Unknown error';
    }

    if (Array.isArray(error.body)) {
        return error.body.map((entry) => entry.message).join(' ');
    }

    return error.body?.message || error.message || 'Unexpected error.';
}
