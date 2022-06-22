#[test_only]
module HippoSwap::TestShared {

    // The preconditions required by the test suite below:
    // Init Token registry for admin

    use HippoSwap::MockDeploy;
    use HippoSwap::MockCoin::{WUSDT, WUSDC, WDAI, WETH, WBTC, WDOT, WSOL};
    use TokenRegistry::TokenRegistry;
    use AptosFramework::Timestamp;
    use HippoSwap::MockCoin;
    use Std::Signer;
    use HippoSwap::CPScripts;
    use HippoSwap::StableCurveScripts;
    use HippoSwap::PieceSwapScript;
    use HippoSwap::Router;
    use HippoSwap::CPSwap;
    use HippoSwap::StableCurveSwap;
    use HippoSwap::PieceSwap;
    use AptosFramework::Coin;
    use Std::Option;

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

    struct SavePoint<phantom LpTokenType> has key {
        reserve_x: u64,
        reserve_y: u64,
        reserve_lp: u64,
        fee_x: u64,
        fee_y: u64,
        fee_lp: u64,
    }

    #[test_only]
    public fun time_start(core: &signer) {
        Timestamp::set_time_has_started_for_testing(core);
    }

    #[test_only]
    public fun init_regitry_and_mock_coins(admin: &signer) {
        TokenRegistry::initialize(admin);
        MockDeploy::init_coin_and_create_store<WUSDT>(admin, b"USDT", b"USDT", 8);
        MockDeploy::init_coin_and_create_store<WUSDC>(admin, b"USDC", b"USDC", 8);
        MockDeploy::init_coin_and_create_store<WDAI>(admin, b"DAI", b"DAI", 8);
        MockDeploy::init_coin_and_create_store<WETH>(admin, b"ETH", b"ETH", 9);
        MockDeploy::init_coin_and_create_store<WBTC>(admin, b"BTC", b"BTC", 10);
        MockDeploy::init_coin_and_create_store<WDOT>(admin, b"DOT", b"DOT", 6);
        MockDeploy::init_coin_and_create_store<WSOL>(admin, b"SOL", b"SOL", 8);
    }

    #[test_only]
    public fun fund_for_participants<X, Y>(signer: &signer, amount_x: u64, amount_y: u64) {
        MockCoin::faucet_mint_to<X>(signer, amount_x);
        MockCoin::faucet_mint_to<Y>(signer, amount_y);
    }

    #[test_only]
    public fun create_save_point<LpToken>(signer: &signer) {
        move_to<SavePoint<LpToken>>(
            signer,
            SavePoint<LpToken> { reserve_x: 0, reserve_y: 0, reserve_lp: 0, fee_x: 0, fee_y: 0, fee_lp: 0, }
        );

    }

    #[test_only]
    public fun create_pool<X, Y>(signer: &signer, pool_type: u8, lp_name: vector<u8>) {
        let (logo_url, project_url) = (b"", b"");
        if ( pool_type == POOL_TYPE_CONSTANT_PRODUCT ) {
            let addr = Signer::address_of(signer);
            let fee_on = true;
            CPScripts::create_new_pool<X, Y>(signer, addr, fee_on, lp_name, lp_name, lp_name, logo_url, project_url);
            create_save_point<CPSwap::LPToken<X, Y>>(signer);
        } else if ( pool_type == POOL_TYPE_STABLE_CURVE ) {
            let (fee, admin_fee) = (100, 100000);
            StableCurveScripts::create_new_pool<X, Y>(signer, lp_name, lp_name, lp_name, logo_url, project_url, fee, admin_fee);
            create_save_point<StableCurveSwap::LPToken<X, Y>>(signer);
        } else if ( pool_type == POOL_TYPE_PIECEWISE ) {
            let k = ((BILLION * BILLION) as u128);
            let (n1, d1, n2, d2, fee, protocal_fee) = (110, 100, 105, 100, 100, 100);
            PieceSwapScript::create_new_pool<X, Y>(signer, lp_name, lp_name, lp_name, logo_url, project_url, k, n1, d1, n2, d2, fee, protocal_fee);
            create_save_point<PieceSwap::LPToken<X, Y>>(signer);
        }
    }

    #[test_only]
    public fun init_pool_with_first_invest<X, Y>(admin: &signer, investor: &signer, pool_type: u8, lp_name: vector<u8>, amt_x: u64, amt_y: u64) {
        create_pool<X, Y>(admin, pool_type, lp_name);
        MockCoin::faucet_mint_to<X>(investor, amt_x);
        MockCoin::faucet_mint_to<Y>(investor, amt_y);
        Router::add_liquidity_route<X, Y>(investor, pool_type, amt_x, amt_y);
    }


    #[test_only]
    public fun get_pool_reserve_route<X, Y>(pool_type: u8): (u64, u64) {
        if (pool_type == POOL_TYPE_CONSTANT_PRODUCT) {
            CPSwap::token_balances<X, Y>()
        } else if (pool_type == POOL_TYPE_STABLE_CURVE) {
            StableCurveSwap::get_reserve_amounts<X, Y>()
        } else if (pool_type == POOL_TYPE_PIECEWISE) {
            PieceSwap::get_reserve_amounts<X, Y>()
        } else {
            abort E_UNKNOWN_POOL_TYPE
        }
    }

    #[test_only]
    public fun assert_pool_reserve<X, Y>(pool_type: u8, predict_x: u64, predict_y: u64) {
        let ( reserve_x, reserve_y ) = get_pool_reserve_route<X, Y>(pool_type);
        assert!(predict_x == reserve_x, E_BALANCE_PREDICTION);
        assert!(predict_y == reserve_y, E_BALANCE_PREDICTION);
    }

    #[test_only]
    public fun debug_print_pool_reserve_xy<X, Y>(pool_type: u8) {
        let ( reserve_x, reserve_y ) = get_pool_reserve_route<X, Y>(pool_type);
        Std::Debug::print(&LABEL_RESERVE_XY);
        Std::Debug::print(&reserve_x);
        Std::Debug::print(&reserve_y);
    }

    #[test_only]
    public fun get_pool_lp_supply_route<X, Y>(pool_type: u8): u64 {
        if (pool_type == POOL_TYPE_CONSTANT_PRODUCT) {
            Option::get_with_default(&Coin::supply<CPSwap::LPToken<X, Y>>(), 0u64)
        } else if (pool_type == POOL_TYPE_STABLE_CURVE) {
            Option::get_with_default(&Coin::supply<StableCurveSwap::LPToken<X, Y>>(), 0u64)
        } else if (pool_type == POOL_TYPE_PIECEWISE) {
            Option::get_with_default(&Coin::supply<PieceSwap::LPToken<X, Y>>(), 0u64)
        } else {
            abort E_UNKNOWN_POOL_TYPE
        }
    }

    #[test_only]
    public fun assert_pool_lp_supply<X, Y>(pool_type: u8, predict_lp: u64) {
        let supply = get_pool_lp_supply_route<X, Y>(pool_type);
        assert!(supply == predict_lp, E_BALANCE_PREDICTION);
    }

    #[test_only]
    public fun debug_print_pool_lp_supply<X, Y>(pool_type: u8) {
        let supply = get_pool_lp_supply_route<X, Y>(pool_type);
        Std::Debug::print(&LABEL_LPTOKEN_SUPPLY);
        Std::Debug::print(&supply);
    }

    #[test_only]
    public fun get_pool_fee_route<X, Y>(pool_type: u8): (u64, u64, u64) {
        if (pool_type == POOL_TYPE_CONSTANT_PRODUCT) {
            // The fee of CP Pool is LPToken minted to the address stored in the metadata.
            // For test purpose we simply keep it as the LPToken balance of the admin address.
            let fee_balance = Coin::balance<CPSwap::LPToken<X, Y>>(ADMIN);
            (0, 0, fee_balance)
        } else if (pool_type == POOL_TYPE_STABLE_CURVE) {
            let (fee_x, fee_y ) = StableCurveSwap::get_fee_amounts<X, Y>();
            (fee_x, fee_y, 0)
        } else if (pool_type == POOL_TYPE_PIECEWISE) {
            let (fee_x, fee_y ) = PieceSwap::get_fee_amounts<X, Y>();
            (fee_x, fee_y, 0)
        } else {
            abort E_UNKNOWN_POOL_TYPE
        }
    }

    #[test_only]
    public fun assert_pool_fee<X, Y>(pool_type: u8, predict_x: u64, predict_y: u64, predict_lp: u64) {
        let (fee_x, fee_y, fee_lp) = get_pool_fee_route<X, Y>(pool_type);
        assert!(predict_x == fee_x, E_BALANCE_PREDICTION);
        assert!(predict_y == fee_y, E_BALANCE_PREDICTION);
        assert!(predict_lp == fee_lp, E_BALANCE_PREDICTION);
    }

    #[test_only]
    public fun debug_print_pool_fee<X, Y>(pool_type: u8) {
        let (fee_x, fee_y, fee_lp) = get_pool_fee_route<X, Y>(pool_type);
        Std::Debug::print(&LABEL_FEE);
        Std::Debug::print(&fee_x);
        Std::Debug::print(&fee_y);
        Std::Debug::print(&fee_lp);
    }

    #[test_only]
    public fun sync_save_point_with_data<T>(
        p: &mut SavePoint<T>, reserve_x: u64, reserve_y: u64, reserve_lp: u64, fee_x: u64, fee_y: u64, fee_lp: u64
    ) {
        let (ref_resv_x, ref_resv_y, ref_resv_lp, ref_fee_x, ref_fee_y, ref_fee_lp) = (
            &mut p.reserve_x, &mut p.reserve_y, &mut p.reserve_lp, &mut p.fee_x, &mut p.fee_y, &mut p.fee_lp
        );
        *ref_resv_x = reserve_x;
        *ref_resv_y = reserve_y;
        *ref_resv_lp = reserve_lp;
        *ref_fee_x = fee_x;
        *ref_fee_y = fee_y;
        *ref_fee_lp = fee_lp;
    }


    #[test_only]
    public fun sync_save_point<X, Y>(pool_type: u8) acquires SavePoint {
        let (fee_x, fee_y, fee_lp) = get_pool_fee_route<X, Y>(pool_type);
        let ( reserve_x, reserve_y ) = get_pool_reserve_route<X, Y>(pool_type);
        let supply = get_pool_lp_supply_route<X, Y>(pool_type);
        if (pool_type == POOL_TYPE_CONSTANT_PRODUCT) {
            let save_point = borrow_global_mut<SavePoint<CPSwap::LPToken<X, Y>>>(ADMIN);
            sync_save_point_with_data(save_point, reserve_x, reserve_y, supply, fee_x, fee_y, fee_lp)
        } else if (pool_type == POOL_TYPE_STABLE_CURVE) {
            let save_point = borrow_global_mut<SavePoint<StableCurveSwap::LPToken<X, Y>>>(ADMIN);
            sync_save_point_with_data(save_point, reserve_x, reserve_y, supply, fee_x, fee_y, fee_lp)
        } else if (pool_type == POOL_TYPE_PIECEWISE) {
            let save_point = borrow_global_mut<SavePoint<PieceSwap::LPToken<X, Y>>>(ADMIN);
            sync_save_point_with_data(save_point, reserve_x, reserve_y, supply, fee_x, fee_y, fee_lp)
        } else {
            abort E_UNKNOWN_POOL_TYPE
        }
    }

    #[test_only]
    public fun debug_print_save_point_info<LpToken>(sp: &mut SavePoint<LpToken>) {
        Std::Debug::print(&LABEL_SAVE_POINT);
        Std::Debug::print(&sp.reserve_x);
        Std::Debug::print(&sp.reserve_y);
        Std::Debug::print(&sp.reserve_lp);
        Std::Debug::print(&sp.fee_x);
        Std::Debug::print(&sp.fee_x);
        Std::Debug::print(&sp.fee_lp);
    }

    #[test_only]
    public fun debug_print_save_point<X, Y>(pool_type: u8) acquires SavePoint {
        if (pool_type == POOL_TYPE_CONSTANT_PRODUCT) {
            let save_point = borrow_global_mut<SavePoint<CPSwap::LPToken<X, Y>>>(ADMIN);
            debug_print_save_point_info(save_point)
        } else if (pool_type == POOL_TYPE_STABLE_CURVE) {
            let save_point = borrow_global_mut<SavePoint<StableCurveSwap::LPToken<X, Y>>>(ADMIN);
            debug_print_save_point_info(save_point)
        } else if (pool_type == POOL_TYPE_PIECEWISE) {
            let save_point = borrow_global_mut<SavePoint<PieceSwap::LPToken<X, Y>>>(ADMIN);
            debug_print_save_point_info(save_point)
        } else {
            abort E_UNKNOWN_POOL_TYPE
        }
    }
}
