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
    use HippoSwap::CPSwap;
    use HippoSwap::StableCurveSwap;
    use HippoSwap::PieceSwap;
    use AptosFramework::Coin;
    use Std::Option;

    const ADMIN: address = @HippoSwap;
    const INVESTOR: address = @0x2FFF;
    const SWAPPER: address = @0x2FFE;

    const POOL_TYPE_CONSTANT_PRODUCT: u8 = 1;
    const POOL_TYPE_STABLE_CURVE: u8 = 2;
    const POOL_TYPE_PIECEWISE: u8 = 3;

    const E_NOT_IMPLEMENTED: u64 = 0;
    const E_UNKNOWN_POOL_TYPE: u64 = 1;
    const E_BALANCE_PREDICTION: u64 = 2;
    const E_DELTA_AMOUNT: u64 = 3;

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

    const LABEL_COMPARE: u128 = 333000000000000000000000000000000000000;
    const LABEL_SAVE_POINT: u128 = 333000000000000000000000000000000000001;
    const LABEL_POOL: u128 = 333000000000000000000000000000000000002;
    const LABEL_RESERVE_XY: u128 = 333000000000000000000000000000000000003;
    const LABEL_FEE: u128 = 333000000000000000000000000000000000004;
    const LABEL_LPTOKEN_SUPPLY: u128 = 333000000000000000000000000000000000005;

    const INC: u8 = 0;
    const DEC: u8 = 1;

    const E_RESERVE_X: u64 = 11;
    const E_RESERVE_Y: u64 = 12;
    const E_RESERVE_LP: u64 = 13;
    const E_FEE_X: u64 = 14;
    const E_FEE_Y: u64 = 15;
    const E_FEE_LP: u64 = 16;

    const E_WALLET_X: u64 = 21;
    const E_WALLET_Y: u64 = 22;
    const E_WALLET_LP: u64 = 23;


    struct PoolSavePoint<phantom LpTokenType> has key, drop {
        reserve_x: u64,
        reserve_y: u64,
        reserve_lp: u64,
        fee_x: u64,
        fee_y: u64,
        fee_lp: u64,
    }

    struct PoolValue has drop {
        reserve_x: u64,
        reserve_y: u64,
        reserve_lp: u64,
        fee_x: u64,
        fee_y: u64,
        fee_lp: u64,
    }

    struct WalletBalanceSavePoint has key, drop {
        coin_x: u64,
        coin_y: u64,
        coin_lp: u64,
    }

    #[test_only]
    public fun time_start(core: &signer) {
        Timestamp::set_time_has_started_for_testing(core);
    }

    #[test_only]
    public fun init_registry_and_mock_coins(admin: &signer) {
        TokenRegistry::initialize(admin);
        MockDeploy::init_coin_and_create_store<WUSDT>(admin, b"USDT", b"USDT", 8);
        MockDeploy::init_coin_and_create_store<WUSDC>(admin, b"USDC", b"USDC", 8);
        MockDeploy::init_coin_and_create_store<WDAI>(admin, b"DAI", b"DAI", 7);
        MockDeploy::init_coin_and_create_store<WETH>(admin, b"ETH", b"ETH", 9);
        MockDeploy::init_coin_and_create_store<WBTC>(admin, b"BTC", b"BTC", 10);
        MockDeploy::init_coin_and_create_store<WDOT>(admin, b"DOT", b"DOT", 6);
        MockDeploy::init_coin_and_create_store<WSOL>(admin, b"SOL", b"SOL", 8);
    }

    #[test_only]
    public fun init_mock_coin_pair<X, Y>(admin: &signer, decimal_x: u64, decimal_y: u64) {
        TokenRegistry::initialize(admin);
        MockDeploy::init_coin_and_create_store<X>(admin, b"COIN-X", b"COIN-X", decimal_x);
        MockDeploy::init_coin_and_create_store<Y>(admin, b"COIN-Y", b"COIN-Y", decimal_y);
    }

    #[test_only]
    public fun fund_for_participants<X, Y>(signer: &signer, amount_x: u64, amount_y: u64) {
        MockCoin::faucet_mint_to<X>(signer, amount_x);
        MockCoin::faucet_mint_to<Y>(signer, amount_y);
    }

    #[test_only]
    public fun create_save_point<LpToken>(signer: &signer) {
        move_to<PoolSavePoint<LpToken>>(
            signer,
            PoolSavePoint<LpToken>{ reserve_x: 0, reserve_y: 0, reserve_lp: 0, fee_x: 0, fee_y: 0, fee_lp: 0, }
        );
    }

    #[test_only]
    public fun create_pool<X, Y>(signer: &signer, pool_type: u8,
       k: u128, n1: u128, d1: u128, n2: u128, d2: u128, fee: u64, protocal_fee: u64
    ) {
        let lp_name = b"TEST-POOL";
        let (logo_url, project_url) = (b"", b"");
        if ( pool_type == POOL_TYPE_CONSTANT_PRODUCT ) {
            let addr = Signer::address_of(signer);
            let fee_on = true;
            CPScripts::create_new_pool<X, Y>(signer, addr, fee_on, lp_name, lp_name, lp_name, logo_url, project_url);
            create_save_point<CPSwap::LPToken<X, Y>>(signer);
        } else if ( pool_type == POOL_TYPE_STABLE_CURVE ) {
            StableCurveScripts::create_new_pool<X, Y>(signer, lp_name, lp_name, lp_name, logo_url, project_url, fee, protocal_fee);
            create_save_point<StableCurveSwap::LPToken<X, Y>>(signer);
        } else if ( pool_type == POOL_TYPE_PIECEWISE ) {
            PieceSwapScript::create_new_pool<X, Y>(signer, lp_name, lp_name, lp_name, logo_url, project_url, k, n1, d1, n2, d2, fee, protocal_fee);
            create_save_point<PieceSwap::LPToken<X, Y>>(signer);
        }
    }



    #[test_only]
    public fun init_debug_utils_for_user<X, Y>(signer: &signer, pool_type: u8) {
        Coin::register_internal<X>(signer);
        Coin::register_internal<Y>(signer);
        if ( pool_type == POOL_TYPE_CONSTANT_PRODUCT ) {
            Coin::register_internal<CPSwap::LPToken<X, Y>>(signer);
        } else if ( pool_type == POOL_TYPE_STABLE_CURVE ) {
            Coin::register_internal<StableCurveSwap::LPToken<X, Y>>(signer);
        } else if ( pool_type == POOL_TYPE_PIECEWISE ) {
            Coin::register_internal<PieceSwap::LPToken<X, Y>>(signer);
        };
        move_to<WalletBalanceSavePoint>(signer, WalletBalanceSavePoint{ coin_x: 0, coin_y: 0, coin_lp: 0, });
    }

    #[test_only]
    public fun prepare_for_test<X, Y>(
        admin: &signer, investor: &signer, swapper: &signer, core: &signer,
        pool_type: u8, decimal_x: u64, decimal_y: u64,
        k: u128, n1: u128, d1: u128, n2: u128, d2: u128, fee: u64, protocal_fee: u64
    ) {
        time_start(core);
        init_mock_coin_pair<X, Y>(admin, decimal_x, decimal_y);
        create_pool<X, Y>(
            admin, pool_type,
            k, n1, d1, n2, d2, fee, protocal_fee
        );
        init_debug_utils_for_user<X, Y>(investor, pool_type);
        init_debug_utils_for_user<X, Y>(swapper, pool_type);
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
        let (reserve_x, reserve_y) = get_pool_reserve_route<X, Y>(pool_type);
        assert!(predict_x == reserve_x, E_BALANCE_PREDICTION);
        assert!(predict_y == reserve_y, E_BALANCE_PREDICTION);
    }

    #[test_only]
    public fun debug_print_pool_reserve_xy<X, Y>(pool_type: u8) {
        let (reserve_x, reserve_y) = get_pool_reserve_route<X, Y>(pool_type);
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
            let (fee_x, fee_y) = StableCurveSwap::get_fee_amounts<X, Y>();
            (fee_x, fee_y, 0)
        } else if (pool_type == POOL_TYPE_PIECEWISE) {
            let (fee_x, fee_y) = PieceSwap::get_fee_amounts<X, Y>();
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
    public fun debug_print_pool<X, Y>(pool_type: u8) {
        let (reserve_x, reserve_y) = get_pool_reserve_route<X, Y>(pool_type);
        let reserve_lp = get_pool_lp_supply_route<X, Y>(pool_type);
        let (fee_x, fee_y, fee_lp) = get_pool_fee_route<X, Y>(pool_type);
        let s = PoolValue{ reserve_x, reserve_y, reserve_lp, fee_x, fee_y, fee_lp };
        Std::Debug::print(&s);
    }

    #[test_only]
    public fun debug_print_comparision<X, Y>(pool_type: u8, ) acquires PoolSavePoint {
        Std::Debug::print(&LABEL_COMPARE);
        debug_print_save_point<X, Y>(pool_type);
        debug_print_pool<X, Y>(pool_type);
    }

    #[test_only]
    public fun sync_save_point_with_data<T>(
        p: &mut PoolSavePoint<T>, reserve_x: u64, reserve_y: u64, reserve_lp: u64, fee_x: u64, fee_y: u64, fee_lp: u64
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
    public fun sync_save_point<X, Y>(pool_type: u8) acquires PoolSavePoint {
        let (fee_x, fee_y, fee_lp) = get_pool_fee_route<X, Y>(pool_type);
        let (reserve_x, reserve_y) = get_pool_reserve_route<X, Y>(pool_type);
        let supply = get_pool_lp_supply_route<X, Y>(pool_type);
        if (pool_type == POOL_TYPE_CONSTANT_PRODUCT) {
            let save_point = borrow_global_mut<PoolSavePoint<CPSwap::LPToken<X, Y>>>(ADMIN);
            sync_save_point_with_data(save_point, reserve_x, reserve_y, supply, fee_x, fee_y, fee_lp)
        } else if (pool_type == POOL_TYPE_STABLE_CURVE) {
            let save_point = borrow_global_mut<PoolSavePoint<StableCurveSwap::LPToken<X, Y>>>(ADMIN);
            sync_save_point_with_data(save_point, reserve_x, reserve_y, supply, fee_x, fee_y, fee_lp)
        } else if (pool_type == POOL_TYPE_PIECEWISE) {
            let save_point = borrow_global_mut<PoolSavePoint<PieceSwap::LPToken<X, Y>>>(ADMIN);
            sync_save_point_with_data(save_point, reserve_x, reserve_y, supply, fee_x, fee_y, fee_lp)
        } else {
            abort E_UNKNOWN_POOL_TYPE
        }
    }

    #[test_only]
    public fun debug_print_save_point_info<LpToken>(sp: &mut PoolSavePoint<LpToken>) {
        let s = PoolValue{
            reserve_x: sp.reserve_x, reserve_y: sp.reserve_y, reserve_lp: sp.reserve_lp,
            fee_x: sp.fee_x, fee_y: sp.fee_y, fee_lp: sp.fee_lp
        };
        Std::Debug::print(&s);
    }

    #[test_only]
    public fun debug_print_save_point<X, Y>(pool_type: u8) acquires PoolSavePoint {
        if (pool_type == POOL_TYPE_CONSTANT_PRODUCT) {
            let save_point = borrow_global_mut<PoolSavePoint<CPSwap::LPToken<X, Y>>>(ADMIN);
            debug_print_save_point_info(save_point)
        } else if (pool_type == POOL_TYPE_STABLE_CURVE) {
            let save_point = borrow_global_mut<PoolSavePoint<StableCurveSwap::LPToken<X, Y>>>(ADMIN);
            debug_print_save_point_info(save_point)
        } else if (pool_type == POOL_TYPE_PIECEWISE) {
            let save_point = borrow_global_mut<PoolSavePoint<PieceSwap::LPToken<X, Y>>>(ADMIN);
            debug_print_save_point_info(save_point)
        } else {
            abort E_UNKNOWN_POOL_TYPE
        }
    }

    #[test_only]
    fun difference(a: u64, b: u64):u64 {
        if (a>b) a-b else b-a
    }

    #[test_only]
    fun assert_delta(sign: u8, delta: u64, current: u64, origin: u64, error_type: u64) {
        if (sign == INC) {
            assert!(difference(delta, current - origin) <= 1, error_type)
        } else {
            assert!(difference(delta, origin - current) <= 1, error_type)
        }
    }

    #[test_only]
    fun assert_pool_delta_content<LpToken>(
        sp: &mut PoolSavePoint<LpToken>,
        sign_reserve_x: u8,
        sign_reserve_y: u8,
        sign_reserve_lp: u8,
        sign_fee_x: u8,
        sign_fee_y: u8,
        sign_fee_lp: u8,
        delta_reserve_x: u64,
        delta_reserve_y: u64,
        delta_reserve_lp: u64,
        delta_fee_x: u64,
        delta_fee_y: u64,
        delta_fee_lp: u64,
        reserve_x: u64,
        reserve_y: u64,
        reserve_lp: u64,
        fee_x: u64,
        fee_y: u64,
        fee_lp: u64,
    ) {
        assert_delta(sign_reserve_x, delta_reserve_x, reserve_x, sp.reserve_x, E_RESERVE_X);
        assert_delta(sign_reserve_y, delta_reserve_y, reserve_y, sp.reserve_y, E_RESERVE_Y);
        assert_delta(sign_reserve_lp, delta_reserve_lp, reserve_lp, sp.reserve_lp, E_RESERVE_LP);
        assert_delta(sign_fee_x, delta_fee_x, fee_x, sp.fee_x, E_FEE_X);
        assert_delta(sign_fee_y, delta_fee_y, fee_y, sp.fee_y, E_FEE_Y);
        assert_delta(sign_fee_lp, delta_fee_lp, fee_lp, sp.fee_lp, E_FEE_LP);
    }

    #[test_only]
    public fun assert_pool_delta<X, Y>(
        pool_type: u8,
        with_sync: bool,
        sign_reserve_x: u8,
        sign_reserve_y: u8,
        sign_reserve_lp: u8,
        sign_fee_x: u8,
        sign_fee_y: u8,
        sign_fee_lp: u8,
        delta_reserve_x: u64,
        delta_reserve_y: u64,
        delta_reserve_lp: u64,
        delta_fee_x: u64,
        delta_fee_y: u64,
        delta_fee_lp: u64,
    ) acquires PoolSavePoint {
        let (fee_x, fee_y, fee_lp) = get_pool_fee_route<X, Y>(pool_type);
        let (reserve_x, reserve_y) = get_pool_reserve_route<X, Y>(pool_type);
        let supply = get_pool_lp_supply_route<X, Y>(pool_type);
        if (pool_type == POOL_TYPE_CONSTANT_PRODUCT) {
            let save_point = borrow_global_mut<PoolSavePoint<CPSwap::LPToken<X, Y>>>(ADMIN);
            assert_pool_delta_content(
                save_point,
                sign_reserve_x, sign_reserve_y, sign_reserve_lp,
                sign_fee_x, sign_fee_y, sign_fee_lp,
                delta_reserve_x, delta_reserve_y, delta_reserve_lp,
                delta_fee_x, delta_fee_y, delta_fee_lp,
                reserve_x, reserve_y, supply,
                fee_x, fee_y, fee_lp,
            );
        } else if (pool_type == POOL_TYPE_STABLE_CURVE) {
            let save_point = borrow_global_mut<PoolSavePoint<StableCurveSwap::LPToken<X, Y>>>(ADMIN);
            assert_pool_delta_content(
                save_point,
                sign_reserve_x, sign_reserve_y, sign_reserve_lp,
                sign_fee_x, sign_fee_y, sign_fee_lp,
                delta_reserve_x, delta_reserve_y, delta_reserve_lp,
                delta_fee_x, delta_fee_y, delta_fee_lp,
                reserve_x, reserve_y, supply,
                fee_x, fee_y, fee_lp,
            );
        } else if (pool_type == POOL_TYPE_PIECEWISE) {
            let save_point = borrow_global_mut<PoolSavePoint<PieceSwap::LPToken<X, Y>>>(ADMIN);
            assert_pool_delta_content(
                save_point,
                sign_reserve_x, sign_reserve_y, sign_reserve_lp,
                sign_fee_x, sign_fee_y, sign_fee_lp,
                delta_reserve_x, delta_reserve_y, delta_reserve_lp,
                delta_fee_x, delta_fee_y, delta_fee_lp,
                reserve_x, reserve_y, supply,
                fee_x, fee_y, fee_lp,
            );
        } else {
            abort E_UNKNOWN_POOL_TYPE
        };
        if (with_sync) {
            sync_save_point<X, Y>(pool_type);
        }
    }

    #[test_only]
    public fun assert_wallet_delta_content<X, Y>(
        sender: &signer,
        sign_coin_x: u8,
        sign_coin_y: u8,
        sign_coin_lp: u8,
        delta_coin_x: u64,
        delta_coin_y: u64,
        delta_coin_lp: u64,
        balance_x: u64,
        balance_y: u64,
        balance_lp: u64,
    ) acquires WalletBalanceSavePoint {
        let addr = Signer::address_of(sender);
        let sp = borrow_global_mut<WalletBalanceSavePoint>(addr);
        assert_delta(sign_coin_x, delta_coin_x, balance_x, sp.coin_x, E_WALLET_X);
        assert_delta(sign_coin_y, delta_coin_y, balance_y, sp.coin_y, E_WALLET_Y);
        assert_delta(sign_coin_lp, delta_coin_lp, balance_lp, sp.coin_lp, E_WALLET_LP);
    }

    #[test_only]
    public fun assert_wallet_delta<X, Y>(
        sender: &signer,
        pool_type: u8,
        with_sync: bool,
        sign_coin_x: u8,
        sign_coin_y: u8,
        sign_coin_lp: u8,
        delta_coin_x: u64,
        delta_coin_y: u64,
        delta_coin_lp: u64,
    ) acquires WalletBalanceSavePoint {
        let (balance_x, balance_y, balance_lp) = get_balance<X, Y>(sender, pool_type);
        assert_wallet_delta_content<X, Y>(sender,
            sign_coin_x, sign_coin_y, sign_coin_lp,
            delta_coin_x, delta_coin_y, delta_coin_lp,
            balance_x, balance_y, balance_lp
        );
        if (with_sync) {
            sync_wallet_save_point<X, Y>(sender, pool_type, );
        }
    }

    #[test_only]
    public fun sync_wallet_save_point_with_data(
        p: &mut WalletBalanceSavePoint, balance_x: u64, balance_y: u64, balance_lp: u64
    ) {
        let (ref_coin_x, ref_coin_y, ref_coin_lp) = (
            &mut p.coin_x, &mut p.coin_y, &mut p.coin_lp
        );
        *ref_coin_x = balance_x;
        *ref_coin_y = balance_y;
        *ref_coin_lp = balance_lp;
    }

    #[test_only]
    public fun sync_wallet_save_point<X, Y>(sender: &signer, pool_type: u8) acquires WalletBalanceSavePoint {
        let addr = Signer::address_of(sender);
        let sp = borrow_global_mut<WalletBalanceSavePoint>(addr);
        let (balance_x, balance_y, balance_lp) = get_balance<X, Y>(sender, pool_type);
        sync_wallet_save_point_with_data(sp, balance_x, balance_y, balance_lp, );
    }

    #[test_only]
    public fun get_balance<X, Y>(sender: &signer, pool_type: u8): (u64, u64, u64) {
        let addr = Signer::address_of(sender);
        let balance_x = Coin::balance<X>(addr);
        let balance_y = Coin::balance<Y>(addr);
        let balance_lp: u64;
        if (pool_type == POOL_TYPE_CONSTANT_PRODUCT) {
            balance_lp = Coin::balance<CPSwap::LPToken<X, Y>>(addr);
        } else if (pool_type == POOL_TYPE_STABLE_CURVE) {
            balance_lp = Coin::balance<StableCurveSwap::LPToken<X, Y>>(addr);
        } else if (pool_type == POOL_TYPE_PIECEWISE) {
            balance_lp = Coin::balance<PieceSwap::LPToken<X, Y>>(addr);
        } else {
            abort E_UNKNOWN_POOL_TYPE
        };
        (balance_x, balance_y, balance_lp)
    }

    #[test_only]
    public fun debug_print_balance<X, Y>(sender: &signer, pool_type: u8) {
        let (coin_x, coin_y, coin_lp) = get_balance<X, Y>(sender, pool_type);
        let s = WalletBalanceSavePoint{
            coin_x, coin_y, coin_lp
        };
        Std::Debug::print(&s);
    }

    #[test_only]
    public fun debug_print_wallet_sp<X, Y>(sender: &signer) acquires WalletBalanceSavePoint {
        let addr = Signer::address_of(sender);
        let sp = borrow_global_mut<WalletBalanceSavePoint>(addr);
        let s = WalletBalanceSavePoint{
            coin_x: sp.coin_x, coin_y: sp.coin_y, coin_lp: sp.coin_lp
        };
        Std::Debug::print(&s);
    }

    #[test_only]
    public fun debug_print_wallet_comparision<X, Y>(sender: &signer, pool_type: u8) acquires WalletBalanceSavePoint {
        debug_print_wallet_sp<X, Y>(sender);
        debug_print_balance<X, Y>(sender, pool_type);
    }
}
