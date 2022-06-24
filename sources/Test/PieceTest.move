#[test_only]
module HippoSwap::PieceTest {

    use HippoSwap::MockCoin::{ WUSDC, WETH};
    use HippoSwap::TestShared;
    use HippoSwap::Router;

    // Keep the consts the same with TestShared.move.


    const ADMIN: address = @HippoSwap;
    const INVESTOR: address = @0x2FFF;
    const SWAPPER: address = @0x2FFE;

    const POOL_TYPE_CONSTANT_PRODUCT:u8 = 1;
    const POOL_TYPE_STABLE_CURVE:u8 = 2;
    const POOL_TYPE_PIECEWISE:u8 = 3;

    const E_NOT_IMPLEMENTED: u64 = 0;
    const E_UNKNOWN_POOL_TYPE: u64 = 1;
    const E_BALANCE_PREDICTION: u64 = 2;

    // 10 to the power of n.
    const P3: u64 = 1000;
    const THOUSAND: u64 = 1000;
    const P4: u64 = 10000;
    const P5: u64 = 100000;
    const P6: u64 = 1000000;
    const MILLION: u64 = 1000000;
    const P7: u64 = 10000000;
    const P8: u64 = 100000000;
    const P9: u64 = 1000000000;
    const BILLION: u64 = 1000000000;
    const P10: u64 = 10000000000;
    const P11: u64 = 100000000000;
    const P12: u64 = 1000000000000;
    const TRILLION: u64 = 1000000000000;
    const P13: u64 = 10000000000000;
    const P14: u64 = 100000000000000;
    const P15: u64 = 1000000000000000;
    const P16: u64 = 10000000000000000;
    const P17: u64 = 100000000000000000;
    const P18: u64 = 1000000000000000000;
    const P19: u64 = 10000000000000000000;

    const LABEL_SAVE_POINT: u128 = 333000000000000000000000000000000000000;
    const LABEL_RESERVE_XY: u128 = 333000000000000000000000000000000000001;
    const LABEL_FEE: u128 = 333000000000000000000000000000000000002;
    const LABEL_LPTOKEN_SUPPLY: u128 = 333000000000000000000000000000000000003;


    // Keep the consts the same with TestShared.move.

    #[test(admin = @HippoSwap, investor = @0x2FFF, swapper = @0x2FFE, core = @0xa550c18)]
    public fun test_pool_piece(admin: &signer, investor: &signer, swapper: &signer, core: &signer) {
        let pool_type = POOL_TYPE_PIECEWISE;
        TestShared::time_start(core);
        TestShared::init_regitry_and_mock_coins(admin);
        TestShared::create_pool<WUSDC, WETH>(admin, pool_type, b"USDC-ETH-PIECE-LP");
        // TODO: Check pool state.
        TestShared::fund_for_participants<WUSDC, WETH>(investor, P8, P9);
        TestShared::fund_for_participants<WUSDC, WETH>(swapper, P8, P9);
        Router::add_liquidity_route<WUSDC, WETH>(investor, pool_type, P8, P9);
        TestShared::debug_print_pool_reserve_xy<WUSDC, WETH>(pool_type);
        TestShared::debug_print_pool_lp_supply<WUSDC, WETH>(pool_type);
        TestShared::debug_print_pool_fee<WUSDC, WETH>(pool_type);
        TestShared::debug_print_save_point<WUSDC, WETH>(pool_type);
        TestShared::sync_save_point<WUSDC, WETH>(pool_type);
        TestShared::debug_print_save_point<WUSDC, WETH>(pool_type);
    }

}
