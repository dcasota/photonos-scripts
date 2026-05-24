/* pr_pypi.h — PyPI JSON-API latest-version detection (python family).
 *
 * See src/pypi.c. For specs whose upstream is PyPI (Source0 on
 * files.pythonhosted.org / pypi.python.org), the authoritative version +
 * download is the JSON API the /project/<pkg>/#files page is rendered from:
 *   GET https://pypi.org/pypi/<pkg>/json
 *     -> {"info":{"version":"X"...}, "urls":[{"packagetype":"sdist",
 *         "filename":"<pkg>-X.tar.gz","url":"https://files.pythonhosted.org/.."}]}
 */
#ifndef PR_PYPI_H
#define PR_PYPI_H

/* GET the PyPI metadata for `package` and return its latest version (heap,
 * caller frees), or NULL on error. When `out_sdist_url`/`out_sdist_name` are
 * non-NULL they receive the latest sdist's download URL and filename (heap,
 * caller frees; set to NULL if no sdist is listed). */
char *pr_pypi_latest_version(const char *package,
                             char **out_sdist_url,
                             char **out_sdist_name);

#endif /* PR_PYPI_H */
