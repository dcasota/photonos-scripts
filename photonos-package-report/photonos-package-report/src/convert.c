/* convert.c — Convert-ToBoolean.
 * Mirrors photonos-package-report.ps1 L 111-118.
 *
 * PS source for reference (verbatim):
 *
 *   # Convert string parameters to boolean (needed when using -File with $true/$false)
 *   function Convert-ToBoolean($value) {
 *       if ($value -is [bool]) { return $value }
 *       if ($value -is [string]) {
 *           if ($value -eq '$true' -or $value -eq 'true' -or $value -eq '1') { return $true }
 *           if ($value -eq '$false' -or $value -eq 'false' -or $value -eq '0') { return $false }
 *       }
 *       return [bool]$value
 *   }
 *
 * In the C port, parameter values always arrive as strings from argv. The
 * "$value -is [bool]" branch therefore never fires here; PS's [bool] cast
 * fallback ("any non-empty non-zero non-null value is true") is emulated
 * by returning 1 when value is non-NULL and non-empty, 0 otherwise.
 */
#include "photonos_package_report.h"

#include <string.h>
#include <strings.h>  /* strcasecmp */

int convert_to_boolean(const char *value)
{
    if (value == NULL) {
        /* PS [bool]$null === $false */
        return 0;
    }

    /* PS string comparisons are case-INSENSITIVE for -eq with strings
     * (PowerShell default). We use strcasecmp to match. */
    if (strcasecmp(value, "$true")  == 0 ||
        strcasecmp(value, "true")   == 0 ||
        strcasecmp(value, "1")      == 0) {
        return 1;
    }
    if (strcasecmp(value, "$false") == 0 ||
        strcasecmp(value, "false")  == 0 ||
        strcasecmp(value, "0")      == 0) {
        return 0;
    }

    /* PS fallback: [bool]$value — any non-empty string is true. */
    return value[0] != '\0' ? 1 : 0;
}
