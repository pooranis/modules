#' Find a module’s source code location
#'
#' @param module character string of the fully qualified module name
#' @return the full path to the corresponding module source code location. If
#' multiple hits are found, return the one with the highest priority, that is
#' coming earlier in the search path, with the local directory having the
#' lowest priority. If no path is found, return \code{NA}.
#'
#' @importFrom tools file_path_sans_ext
#'
find_module = function (module) {
    parts = unlist(strsplit(module, '/'))

    # Use all-but-last parts to construct module source path, last part to
    # determine name of source file.
    suffix = basename(file_path_sans_ext(module))
    module_path = dirname(module)
    file_pattern = sprintf('^%s\\.[rR]$', suffix)

    search_path = if (parts[1] %in% c('.', '..'))
        calling_module_path()
    else
        import_search_path()
    candidate_paths = c(file.path(search_path, module_path), module_path)

    # For each candidate, try finding a module file. A module file is either
    # `{suffix}.r` or `{suffix}/__init__.r`, preceded by the path prefix.
    # Preference is given to `{suffix}.r`.

    find_candidate = function (path) {
        candidate = list.files(path, file_pattern, full.names = TRUE)

        if (length(candidate) == 0)
            list.files(file.path(path, suffix), '^__init__\\.[rR]$',
                       full.names = TRUE)
        else
            candidate
    }

    hits = unlist(lapply(candidate_paths, find_candidate))

    if (length(hits) == 0)
        stop('Unable to load module ', sQuote(module), '; not found in ',
             paste(sQuote(search_path), collapse = ', '))

    normalizePath(unname(hits[1]))
}

calling_module_path = function () {
    # Go up through caller hierarchy until the caller’s `parent.env()` is no
    # longer the same as the `parent.env()` of this function. This indicates
    # that we have reached the actual caller of `import`.
    package_env = parent.env(environment())
    n = 1

    while (identical(parent.env(parent.frame(n)), package_env))
        n = n + 1

    module_base_path(parent.frame(n))
}

#' Return a list of paths to a module’s \code{__init__.r} files
#'
#' @param module character string of the fully qualified module name
#' @param module_path the module’s file path prefix (see \code{Details})
#' @return a vector of paths to the module’s \code{__init__.r} files, in the
#' order in which they need to be executed, or \code{NULL} if the arguments do
#' not resolve to a valid nested module (i.e. not all of the path components
#' which form the qualified module name contain a \code{__init__.r} file).
#' The vector’s \code{names} are the names of the respective modules.
#' @details The \code{module_path} is the fully qualified module path, but
#' without the trailing module file (either \code{x.r} or \code{x/__init__.r}).
module_init_files = function (module, module_path) {
    module_parts = unlist(strsplit(module, '/'))
    module_parts = module_parts[-length(module_parts)]

    has_children = grepl('/__init__\\.[rR]$', module_path)
    path_parts = split_path(module_path)
    path_prefix_length = length(path_parts) - length(module_parts) -
        if (has_children) 2 else 1

    base_path = merge_path(path_parts[seq_len(path_prefix_length)])

    # Find the `__init__.r` files in all path components of `module_parts`.
    # Any `__init__.r` files *upstream* of this path must be disregarded, e.g.
    # for the following path
    #
    #   + a/
    #   +-+ b/
    #   | +-> __init__.r
    #   +-> __init__.r
    #
    # and code
    #
    #   options(import.path = 'a')
    #   import('b')
    #
    # only `a/b/__init__.r` gets executed, not `a/__init__.r`.

    path_prefix = function (i, parts)
        paste(parts[seq_len(i)], collapse = '.')

    partials = seq_along(module_parts)
    partials = setNames(partials, sapply(partials, path_prefix, module_parts))

    build_prefix = function (i)
        list.files(merge_path(c(base_path, module_parts[seq_len(i)])),
                   pattern = '^__init__\\.[rR]$', full.names = TRUE)

    all_prefixes = unlist(sapply(partials, build_prefix))

    if (is.null(all_prefixes) || length(all_prefixes) != length(module_parts))
        NULL
    else
        setNames(normalizePath(all_prefixes), names(all_prefixes))
}

#' Return the import module search path
#'
#' @note The search paths are ordered from highest to lowest priority.
#' The current module’s path always has the lowest priority.
#'
#' There are two ways of modifying the module search path: by default,
#' \code{options('import.path')} specifies the search path. If and only if that
#' is unset, R also considers the environment variable \code{R_IMPORT_PATH}.
import_search_path = function () {
    environment = strsplit(Sys.getenv('R_IMPORT_PATH'), ':')[[1]]
    if (length(environment) == 0)
        environment = NULL
    c(getOption('import.path', environment), module_base_path(parent.frame()))
}

#' Split a path into its components and merge them back together
#'
#' \code{split_path(path)} is a platform independent and file system logic
#' aware alternative to \code{strsplit(path, '/')[[1]]}.
#' @param path the path to split
#' @return \code{split_path} returns a character vector of path components that
#' logically represent \code{path}.
split_path = function (path) {
    if (identical(path, dirname(path)))
        path
    else
        c(Recall(dirname(path)), basename(path))
}

#' \code{merge_path(split_path(path))} is equivalent to \code{path}.
#' @param components character string vector of path components to merge
#' @return \code{merge_path} returns a single character string that is
#' logically equivalent to the \code{path} passed to \code{split_path}.
#' logically represent \code{path}.
#' @note \code{merge_path} is the inverse function to \code{split_path}.
#' However, this does not mean that its result will be identical to the
#' original path. Instead, it is only guaranteed that it will refer to the same
#' logical path given the same working directory.
#' @rdname split_path
merge_path = function (components) {
    do.call(file.path, as.list(components))
}
