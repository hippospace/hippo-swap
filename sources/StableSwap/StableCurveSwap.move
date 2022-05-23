module HippoSwap::StableCurveSwap {
    use Std::ASCII;
    use Std::Option;
    use AptosFramework::Coin;
    use AptosFramework::Timestamp;

    use HippoSwap::HippoConfig;
    use HippoSwap::StableCurveNumeral;

    // Token

    struct LPToken<phantom X, phantom Y> has key, store, copy {}

    struct LPCapability<phantom X, phantom Y> has key, store {
        mint: Coin::MintCapability<LPToken<X, Y>>,
        burn: Coin::BurnCapability<LPToken<X, Y>>,
    }

    // Swap

    struct SwapPair<phantom X, phantom Y> has key, store {
        x_reserve: Coin::Coin<X>,
        y_reserve: Coin::Coin<Y>,
        initial_A: u128,
        future_A: u128,
        initial_A_time: u128,
        future_A_time: u128,
    }


    const DECIMALS: u64 = 18;
    // const PRECISION: u128 = 1000000000000000000;   // 10 ** 18
    const A_PRECISION: u128 = 100;

    const ERROR_SWAP_INVALID_TOKEN_PAIR: u64 = 2000;
    const ERROR_SWAP_BURN_CALC_INVALID: u64 = 2004;
    const ERROR_SWAP_ADDLIQUIDITY_INVALID: u64 = 2007;
    const ERROR_SWAP_TOKEN_NOT_EXISTS: u64 = 2008;
    const ERROR_SWAP_INVALID_DERIVIATION: u64 = 2020;

    // Token utilities

    public fun initialize_coin<X, Y>(signer: &signer, name: ASCII::String, symbol: ASCII::String) {
        assert!(Coin::is_coin_initialized<X>(), ERROR_SWAP_INVALID_TOKEN_PAIR);
        assert!(Coin::is_coin_initialized<Y>(), ERROR_SWAP_INVALID_TOKEN_PAIR);
        let (mint_capability, burn_capability) = Coin::initialize<LPToken<X, Y>>(
            signer, name, symbol, DECIMALS, true
        );
        move_to(signer, LPCapability{ mint: mint_capability, burn: burn_capability });
    }

    fun mint<X, Y>(amount: u64): Coin::Coin<LPToken<X, Y>> acquires LPCapability {
        let liquidity_cap = borrow_global<LPCapability<X, Y>>(HippoConfig::admin_address());
        let mint_token = Coin::mint<LPToken<X, Y>>(amount, &liquidity_cap.mint);
        mint_token
    }

    fun burn<X: copy + store, Y: copy + store>(to_burn: Coin::Coin<LPToken<X, Y>>,
    ) acquires LPCapability {
        let liquidity_cap = borrow_global<LPCapability<X, Y>>(HippoConfig::admin_address());
        Coin::burn<LPToken<X, Y>>(to_burn, &liquidity_cap.burn);
    }

//    public fun balance<X, Y>(): u64 {
//        Coin::balance<LPToken<X, Y>>(HippoConfig::admin_address())
//    }

    #[test_only]
    fun init_mock_coin<Money: store>(creator: &signer): Coin::Coin<Money> {
        use HippoSwap::MockCoin;
        MockCoin::initialize<Money>(creator, 9);
        MockCoin::mint<Money>(20)
    }

    #[test(admin = @HippoSwap, core_resource_account = @CoreResources)]
    fun mint_mock_coin(admin: &signer) acquires LPCapability {
        use HippoSwap::MockCoin;
        MockCoin::initialize<HippoSwap::MockCoin::WETH>(admin, 9);
        MockCoin::initialize<HippoSwap::MockCoin::WDAI>(admin, 9);
        initialize_coin<HippoSwap::MockCoin::WETH, HippoSwap::MockCoin::WDAI>(
            admin,
            ASCII::string(b"Curve:WETH-WDAI"),
            ASCII::string(b"WEWD")
        );
        let coin = mint<HippoSwap::MockCoin::WETH, HippoSwap::MockCoin::WDAI>(100);
        burn(coin)
    }

    // Swap utilities

    public fun get_initial_A<X, Y>(): u128 acquires SwapPair {
        borrow_global<SwapPair<X, Y>>(HippoConfig::admin_address()).initial_A
    }

    public fun get_initial_A_time<X, Y>(): u128 acquires SwapPair {
        borrow_global<SwapPair<X, Y>>(HippoConfig::admin_address()).initial_A_time
    }

    public fun get_future_A_time<X, Y>(): u128 acquires SwapPair {
        borrow_global<SwapPair<X, Y>>(HippoConfig::admin_address()).future_A_time
    }

    public fun get_future_A<X, Y>(): u128 acquires SwapPair {
        borrow_global<SwapPair<X, Y>>(HippoConfig::admin_address()).future_A
    }


    public fun get_reserves<X: copy + store, Y: copy + store>(): (u64, u64) acquires SwapPair {
        let pair = borrow_global<SwapPair<X, Y>>(HippoConfig::admin_address());
        let x_reserve = Coin::value(&pair.x_reserve);
        let y_reserve = Coin::value(&pair.y_reserve);
        (x_reserve, y_reserve)
    }

    fun make_swap_pair<X: copy + store, Y: copy + store>(): SwapPair<X, Y> {
        SwapPair<X, Y>{
            x_reserve: Coin::zero<X>(),
            y_reserve: Coin::zero<Y>(),
            initial_A: 0,
            future_A: 0,
            initial_A_time: 0,
            future_A_time: 0,
        }
    }

    public fun initialize<X: copy + store, Y: copy + store>(signer: &signer, name: ASCII::String, symbol: ASCII::String) {
        initialize_coin<X, Y>(signer, name, symbol);
        let token_pair = make_swap_pair<X, Y>();
        move_to(signer, token_pair);
    }


    fun get_raw_A<X, Y>(): u128 acquires SwapPair {
        let t1 = get_future_A_time<X, Y>();
        let a1 = get_future_A<X, Y>();
        let block_timestamp = (Timestamp::now_seconds() as u128);
        let a0 = get_initial_A<X, Y>();
        let t0 = get_initial_A_time<X, Y>();
        StableCurveNumeral::raw_A(t1, a1, t0, a0, block_timestamp)
    }

    fun rates<X, Y>(): (u128, u128) {
        StableCurveNumeral::rates(Coin::decimals<X>(), Coin::decimals<Y>())
    }

    fun xp_mem<X, Y>(x_reserve: u64, y_reserve: u64): (u128, u128) {
        let (rate_x, rate_y) = rates<X, Y>();
        StableCurveNumeral::xp_mem(x_reserve, y_reserve, rate_x, rate_y)
    }


    fun get_D_mem<X, Y>(x: u64, y: u64, amp: u128): u128 {
        let (new_x, new_y) = xp_mem<X, Y>(x, y);
        StableCurveNumeral::get_D(new_x, new_y, amp)
    }

    public fun deposit_liquidity<X: copy + store, Y: copy + store>(x: Coin::Coin<X>, y: Coin::Coin<Y>,
    ): Coin::Coin<LPToken<X, Y>> acquires SwapPair, LPCapability {
        let (x_reserve, y_reserve) = get_reserves<X, Y>();
        let x_value_prev = Coin::value<X>(&x);
        let y_value_prev = Coin::value<Y>(&y);

        let amp = get_raw_A<X, Y>();
        let d0 = get_D_mem<X, Y>(x_reserve, y_reserve, amp);
        // TODO: Need to be corrected.
        let liquidity = x_value_prev + y_value_prev + (amp as u64) + ( d0 as u64);
        assert!(liquidity > 0, ERROR_SWAP_ADDLIQUIDITY_INVALID);
        let token_pair = borrow_global_mut<SwapPair<X, Y>>(HippoConfig::admin_address());
        Coin::merge(&mut token_pair.x_reserve, x);
        Coin::merge(&mut token_pair.y_reserve, y);
        let mint_token = mint<X, Y>(liquidity);
        update_oracle<X, Y>(x_reserve, y_reserve);
        mint_token
    }

    public fun remove_liquidity<X: copy + store, Y: copy + store>(to_burn: Coin::Coin<LPToken<X, Y>>,
    ): (Coin::Coin<X>, Coin::Coin<Y>) acquires SwapPair, LPCapability {
        let to_burn_value = Coin::value(&to_burn);
        let swap_pair = borrow_global_mut<SwapPair<X, Y>>(HippoConfig::admin_address());
        let x_reserve = Coin::value(&swap_pair.x_reserve);
        let y_reserve = Coin::value(&swap_pair.y_reserve);
        let total_supply = Option::extract(&mut Coin::supply<LPToken<X, Y>>());
        // TODO: Implement the algorithm   !!! Unsafe current
        let x = to_burn_value * x_reserve / total_supply;
        let y = to_burn_value * y_reserve / total_supply;
        // assert!(x > 0 && y > 0, ERROR_SWAP_BURN_CALC_INVALID);
        burn<X, Y>(to_burn);
        let x_coin = Coin::extract(&mut swap_pair.x_reserve, x);
        let y_coin = Coin::extract(&mut swap_pair.y_reserve, y);
        update_oracle<X, Y>(x_reserve, y_reserve);
        (x_coin, y_coin)
    }

    fun update_oracle<X: copy + store, Y: copy + store>(x_reserve: u64, y_reserve: u64, ) acquires SwapPair {
        let token_pair = borrow_global_mut<SwapPair<X, Y>>(HippoConfig::admin_address());
        // TODO: Not implemented.
        token_pair.future_A = ((x_reserve * y_reserve) as u128);
    }


    // Tests

    #[test_only]
    fun genesis(core: &signer){
        use AptosFramework::Genesis;
        Genesis::setup(core);
    }

    #[test_only]
    fun update_time(account: &signer, time: u64) {
        use AptosFramework::Timestamp;
        Timestamp::update_global_time(account, @0x1000010, time);
    }

    #[test_only]
    fun init_lp_token(admin: &signer, core: &signer){

        use HippoSwap::MockCoin;
        genesis(core);

        MockCoin::initialize<MockCoin::WETH>(admin, 18);
        MockCoin::initialize<MockCoin::WDAI>(admin, 18);
        initialize<HippoSwap::MockCoin::WETH, HippoSwap::MockCoin::WDAI>(
            admin,
            ASCII::string(b"Curve:WETH-WDAI"),
            ASCII::string(b"WEWD")
        );

    }

    #[test(admin = @HippoSwap, core = @CoreResources)]
    fun mint_lptoken_coin(admin: &signer, core: &signer) acquires SwapPair, LPCapability {
        use Std::Signer;
        use HippoSwap::MockCoin;
        init_lp_token(admin, core);
        let x = MockCoin::mint<MockCoin::WETH>(10);
        let y = MockCoin::mint<MockCoin::WDAI>(10);
        let liquidity = deposit_liquidity(x, y);
        let (x, y) = remove_liquidity(liquidity);
        Coin::deposit(Signer::address_of(admin), x);
        Coin::deposit(Signer::address_of(admin), y);
    }

    #[test(admin = @HippoSwap,  core = @CoreResources)]
    #[expected_failure(abort_code = 2007)]
    public fun fail_add_liquidity(admin: &signer, core: &signer) acquires SwapPair, LPCapability {
        use Std::Signer;
        use HippoSwap::MockCoin;

        genesis(core);

        MockCoin::initialize<HippoSwap::MockCoin::WETH>(admin, 18);
        MockCoin::initialize<HippoSwap::MockCoin::WDAI>(admin, 18);
        initialize<HippoSwap::MockCoin::WETH, HippoSwap::MockCoin::WDAI>(
            admin,
            ASCII::string(b"Curve:WETH-WDAI"),
            ASCII::string(b"WEWD")
        );
        let x = MockCoin::mint<MockCoin::WETH>(0);
        let y = MockCoin::mint<MockCoin::WDAI>(0);
        let liquidity = deposit_liquidity(x, y);
        Coin::deposit(Signer::address_of(admin), liquidity)
    }

    #[test(admin = @HippoSwap)]
    #[expected_failure(abort_code = 2000)]
    public fun fail_x(admin: &signer) {
        initialize<HippoSwap::MockCoin::WETH, HippoSwap::MockCoin::WDAI>(
            admin,
            ASCII::string(b"Curve:WETH-WDAI"),
            ASCII::string(b"WEWD")
        );
    }

    #[test(admin = @HippoSwap)]
    #[expected_failure(abort_code = 2000)]
    public fun fail_y(admin: &signer) {
        use HippoSwap::MockCoin;
        MockCoin::initialize<HippoSwap::MockCoin::WETH>(admin, 18);
        initialize<HippoSwap::MockCoin::WETH, HippoSwap::MockCoin::WDAI>(
            admin,
            ASCII::string(b"Curve:WETH-WDAI"),
            ASCII::string(b"WEWD")
        );
    }

    #[test(admin = @HippoSwap, core = @CoreResources, vm = @0)]
    fun test_swap_pair_case_A(admin: &signer, core: &signer, vm: &signer) acquires SwapPair {
        use HippoSwap::MockCoin;
        init_lp_token(admin, core);
        let swap_pair = borrow_global_mut<SwapPair<MockCoin::WETH, MockCoin::WDAI>>(HippoConfig::admin_address());
        update_time(vm, 0x1100000);
        let block_timestamp = (Timestamp::now_seconds() as u128);
        swap_pair.future_A_time = block_timestamp + 2;
        swap_pair.future_A = 20;
        swap_pair.initial_A = 4;
        let k = get_raw_A<MockCoin::WETH, MockCoin::WDAI>();
        Std::Debug::print(&k)
    }

    #[test(admin = @HippoSwap, core = @CoreResources, vm = @0)]
    fun test_swap_pair_case_B(admin: &signer, core: &signer, vm: &signer) acquires SwapPair {
        use HippoSwap::MockCoin;
        init_lp_token(admin, core);
        let swap_pair = borrow_global_mut<SwapPair<MockCoin::WETH, MockCoin::WDAI>>(HippoConfig::admin_address());
        update_time(vm, 0x1100000);
        let block_timestamp = (Timestamp::now_seconds() as u128);
        swap_pair.future_A_time = block_timestamp + 2;
        swap_pair.future_A = 4;
        swap_pair.initial_A = 20;
        let k = get_raw_A<MockCoin::WETH, MockCoin::WDAI>();
        Std::Debug::print(&k);
    }

}
