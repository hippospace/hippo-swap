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
    public fun faucet_mint_mock_coins(signer: &signer, amount: u64) {
        MockCoin::faucet_mint_to<WUSDT>(signer, amount);
        MockCoin::faucet_mint_to<WUSDC>(signer, amount);
        MockCoin::faucet_mint_to<WDAI>(signer, amount);
        MockCoin::faucet_mint_to<WETH>(signer, amount);
        MockCoin::faucet_mint_to<WBTC>(signer, amount);
        MockCoin::faucet_mint_to<WDOT>(signer, amount);
        MockCoin::faucet_mint_to<WSOL>(signer, amount);
    }

    #[test_only]
    public fun create_pool<X, Y>(pool_type: u8, lp_name: vector<u8>, signer: &signer) {
        let (logo_url, project_url) = (b"", b"");
        if ( pool_type == POOL_TYPE_CONSTANT_PRODUCT ) {
            let addr = Signer::address_of(signer);
            let fee_on = true;
            CPScripts::create_new_pool<X, Y>(signer, addr, fee_on, lp_name, lp_name, lp_name, logo_url, project_url)
        } else if ( pool_type == POOL_TYPE_STABLE_CURVE ) {
            let (fee, admin_fee) = (100, 100000);
            StableCurveScripts::create_new_pool<X, Y>(signer, lp_name, lp_name, lp_name, logo_url, project_url, fee, admin_fee);
        } else if ( pool_type == POOL_TYPE_PIECEWISE ) {
            let k = ((BILLION * BILLION) as u128);
            let (n1, d1, n2, d2, fee, protocal_fee) = (110, 100, 105, 100, 100, 100);
            PieceSwapScript::create_new_pool<X, Y>(signer, lp_name, lp_name, lp_name, logo_url, project_url, k, n1, d1, n2, d2, fee, protocal_fee);
        }
    }

    #[test_only]
    public fun init_pool_with_first_invest<X, Y>(admin: &signer, investor: &signer, pool_type: u8, lp_name: vector<u8>, amt_x: u64, amt_y: u64) {
        create_pool<X, Y>(pool_type, lp_name, admin);
        MockCoin::faucet_mint_to<X>(investor, amt_x);
        MockCoin::faucet_mint_to<Y>(investor, amt_y);
        Router::add_liquidity_route<X, Y>(investor, pool_type, amt_x, amt_y);
    }

    #[test_only]
    public fun assert_pool_reserve<X, Y>(pool_type: u8, predict_x: u64, predict_y: u64) {
        if (pool_type == POOL_TYPE_CONSTANT_PRODUCT) {
            let (reserve_x, reserve_y) = CPSwap::token_balances<X, Y>();
            assert!(predict_x == reserve_x, E_BALANCE_PREDICTION);
            assert!(predict_y == reserve_y, E_BALANCE_PREDICTION);
        } else if (pool_type == POOL_TYPE_STABLE_CURVE) {
            let (reserve_x, reserve_y ) = StableCurveSwap::get_reserve_amounts<X, Y>();
            assert!(predict_x == reserve_x, E_BALANCE_PREDICTION);
            assert!(predict_y == reserve_y, E_BALANCE_PREDICTION);
        } else if (pool_type == POOL_TYPE_PIECEWISE) {
            let (reserve_x, reserve_y) = PieceSwap::get_reserve_amounts<X, Y>();
            assert!(predict_x == reserve_x, E_BALANCE_PREDICTION);
            assert!(predict_y == reserve_y, E_BALANCE_PREDICTION);
        } else {
            abort E_UNKNOWN_POOL_TYPE
        };
    }


    #[test_only]
    public fun assert_pool_fee<X, Y>(pool_type: u8, predict_x: u64, predict_y: u64, predict_lp: u64) {
        if (pool_type == POOL_TYPE_CONSTANT_PRODUCT) {
            // The fee of CP Pool is LPToken minted to the address stored in the metadata.
            // For test purpose we simply keep it as the LPToken balance of the admin address.
            let fee_balance = Coin::balance<CPSwap::LPToken<X, Y>>(ADMIN);
            assert!(predict_lp == fee_balance, E_BALANCE_PREDICTION);
        } else if (pool_type == POOL_TYPE_STABLE_CURVE) {
            let (fee_x, fee_y ) = StableCurveSwap::get_fee_amounts<X, Y>();
            assert!(predict_x == fee_x, E_BALANCE_PREDICTION);
            assert!(predict_y == fee_y, E_BALANCE_PREDICTION);
        } else if (pool_type == POOL_TYPE_PIECEWISE) {
            let (fee_x, fee_y ) = PieceSwap::get_fee_amounts<X, Y>();
            assert!(predict_x == fee_x, E_BALANCE_PREDICTION);
            assert!(predict_y == fee_y, E_BALANCE_PREDICTION);
        } else {
            abort E_UNKNOWN_POOL_TYPE
        };
    }

}
