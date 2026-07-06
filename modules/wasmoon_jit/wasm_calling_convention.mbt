///|
/// Wasmoon internal Wasm-to-Wasm calling convention for a target ISA.
pub fn wasm_calling_convention_for_isa(
  isa : @isa.ISA,
) -> @abi.CallConventionLayout {
  match isa {
    AArch64 =>
      {
        context_arg: { index: 0, class: Int },
        user_arg_gprs: [
          { index: 1, class: Int },
          { index: 2, class: Int },
          { index: 3, class: Int },
          { index: 4, class: Int },
          { index: 5, class: Int },
          { index: 6, class: Int },
          { index: 7, class: Int },
        ],
        arg_fprs: @abi.aapcs64_arg_fprs(),
        ret_gprs: @abi.aapcs64_ret_gprs(),
        ret_fprs: @abi.aapcs64_ret_fprs(),
      }
    AMD64 => {
      let arg_fprs : Array[@abi.PReg] = []
      let ret_fprs : Array[@abi.PReg] = []
      for i in 0..<8 {
        arg_fprs.push({ index: i, class: Float64 })
        ret_fprs.push({ index: i, class: Float64 })
      }
      {
        context_arg: { index: 7, class: Int },
        user_arg_gprs: [
          { index: 6, class: Int },
          { index: 2, class: Int },
          { index: 1, class: Int },
          { index: 8, class: Int },
          { index: 9, class: Int },
        ],
        arg_fprs,
        ret_gprs: [
          { index: 0, class: Int },
          { index: 2, class: Int },
          { index: 1, class: Int },
          { index: 8, class: Int },
          { index: 9, class: Int },
          { index: 6, class: Int },
          { index: 7, class: Int },
          { index: 10, class: Int },
        ],
        ret_fprs,
      }
    }
  }
}

///|
pub fn wasm_calling_convention() -> @abi.CallConventionLayout {
  wasm_calling_convention_for_isa(@isa.ISA::current())
}
