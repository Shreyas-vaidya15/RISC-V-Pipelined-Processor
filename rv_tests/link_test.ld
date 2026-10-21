ENTRY(_start)
SECTIONS {
  .text 0 : { *(.text.init) *(.text*) }
  .data 0 : AT(0x10000) { *(.data*) }
}
