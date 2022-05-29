/// Uniswap v2 like token swap program
module HippoSwap::CPSwapUtils {
    use HippoSwap::SafeMath;

    const ERROR_INSUFFICIENT_INPUT_AMOUNT: u64 = 0;
    const ERROR_INSUFFICIENT_LIQUIDITY: u64 = 1;

    public fun get_amount_out(
        amount_in: u64,
        reserve_in: u64,
        reserve_out: u64
    ): u64 {
        assert!(amount_in > 0, ERROR_INSUFFICIENT_INPUT_AMOUNT);
        assert!(reserve_in > 0 && reserve_out > 0, ERROR_INSUFFICIENT_LIQUIDITY);

        let amount_in_with_fee = SafeMath::mul(
            (amount_in as u128),
            997u128
        );
        let numerator = SafeMath::mul(amount_in_with_fee, (reserve_out as u128));
        let denominator = SafeMath::mul((reserve_in as u128), 1000u128) + amount_in_with_fee;
        (SafeMath::div(numerator, denominator) as u64)
    }

    #[test]
    fun test_get_amount_out() {
        let a = get_amount_out(100, 10, 10);
        Std::Debug::print(&a);
        assert!(a > 0, 0);
    }
}