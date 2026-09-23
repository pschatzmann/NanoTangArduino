/* Empty default for yield(), which delay() and many libraries call while
 * waiting; a sketch or library can override it with its own definition. */
void yield(void) __attribute__((weak));
void yield(void)
{
}
