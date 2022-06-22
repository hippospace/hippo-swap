address HippoSwap {
module PieceSwap {
    /*
    PieceSwap uses 3 distinct constant-product curves, joined together in a piecewise fashion, to create a continuous
     and smooth curve that has:
    - low slippage in the middle range
    - higher slippage in the ending range
    */

    use AptosFramework::Coin;
    use Std::Signer;
    use Std::ASCII;
    use HippoSwap::PieceSwapMath;
    use HippoSwap::Math;

    const MODULE_ADMIN: address = @HippoSwap;
    const MINIMUM_LIQUIDITY: u128 = 1000;
    const ERROR_ONLY_ADMIN: u64 = 0;
    const ERROR_ALREADY_INITIALIZED: u64 = 1;
    const ERROR_COIN_NOT_INITIALIZED: u64 = 2;
    const ERROR_NOT_CREATOR: u64 = 3;

    struct LPToken<phantom X, phantom Y> {}

    struct PieceSwapPoolInfo<phantom X, phantom Y> has key {
        reserve_x: Coin::Coin<X>,
        reserve_y: Coin::Coin<Y>,
        lp_amt: u64,
        lp_mint_cap: Coin::MintCapability<LPToken<X,Y>>,
        lp_burn_cap: Coin::BurnCapability<LPToken<X,Y>>,
        K: u128,
        K2: u128,
        Xa: u128,
        Xb: u128,
        m: u128,
        n: u128,
        x_deci_mult: u64,
        y_deci_mult: u64,
        // how much of the swap output is taken as swap fees
        swap_fee_per_million: u64,
        // how much of the swap fees are given to protocol instead of LPs
        protocol_fee_share_per_thousand: u64,
        protocol_fee_x: Coin::Coin<X>,
        protocol_fee_y: Coin::Coin<Y>,
    }

    public fun create_new_pool<X, Y>(
        admin: &signer,
        lp_name: vector<u8>,
        lp_symbol: vector<u8>,
        lp_decimals: u64,
        k: u128,
        w1_numerator: u128,
        w1_denominator: u128,
        w2_numerator: u128,
        w2_denominator: u128,
        swap_fee_per_million: u64,
        protocol_fee_share_per_thousand: u64,
    ) {
        /*
        1. make sure admin is right
        2. make sure hasn't already been initialized
        3. initialize LP
        4. initialize PieceSwapPoolInfo
        5. Create LP CoinStore for admin (for storing minimum_liquidity)
        */
        // 1
        let admin_addr = Signer::address_of(admin);
        assert!(admin_addr == MODULE_ADMIN, ERROR_NOT_CREATOR);

        // 2
        assert!(!exists<PieceSwapPoolInfo<X, Y>>(admin_addr), ERROR_ALREADY_INITIALIZED);
        assert!(!exists<PieceSwapPoolInfo<Y, X>>(admin_addr), ERROR_ALREADY_INITIALIZED);
        assert!(Coin::is_coin_initialized<X>(), ERROR_COIN_NOT_INITIALIZED);
        assert!(Coin::is_coin_initialized<Y>(), ERROR_COIN_NOT_INITIALIZED);

        // 3. initialize LP
        let (lp_mint_cap, lp_burn_cap) = Coin::initialize<LPToken<X,Y>>(
            admin,
            ASCII::string(lp_name),
            ASCII::string(lp_symbol),
            lp_decimals,
            true,
        );

        // 4.
        let (xa, xb, m, n, k2) = PieceSwapMath::compute_initialization_constants(
            k,
            w1_numerator,
            w1_denominator,
            w2_numerator,
            w2_denominator
        );
        let x_decimals = Coin::decimals<X>();
        let y_decimals = Coin::decimals<Y>();
        let (x_deci_mult, y_deci_mult) =
        if (x_decimals > y_decimals) {
            (1u128, Math::pow(10, ((x_decimals - y_decimals) as u8)))
        }
        else if (y_decimals > x_decimals){
            (Math::pow(10, ((y_decimals - x_decimals) as u8)), 1u128)
        } else {
            (1u128, 1u128)
        };

        move_to<PieceSwapPoolInfo<X, Y>>(
            admin,
            PieceSwapPoolInfo<X,Y> {
                reserve_x: Coin::zero<X>(),
                reserve_y: Coin::zero<Y>(),
                lp_amt: 0,
                lp_mint_cap,
                lp_burn_cap,
                K: k,
                K2: k2,
                Xa: xa,
                Xb: xb,
                m,
                n,
                x_deci_mult: (x_deci_mult as u64),
                y_deci_mult: (y_deci_mult as u64),
                swap_fee_per_million,
                protocol_fee_share_per_thousand,
                protocol_fee_x: Coin::zero<X>(),
                protocol_fee_y: Coin::zero<Y>(),
            }
        );

        // 5.
        Coin::register_internal<LPToken<X, Y>>(admin);
    }

    public fun add_liquidity<X, Y>(
        sender: &signer,
        add_amt_x: u64,
        add_amt_y: u64,
    ): (u64, u64, u64) acquires PieceSwapPoolInfo {
        let pool = borrow_global_mut<PieceSwapPoolInfo<X, Y>>(MODULE_ADMIN);
        let current_x = (Coin::value(&pool.reserve_x) as u128) * (pool.x_deci_mult as u128);
        let current_y = (Coin::value(&pool.reserve_y) as u128) * (pool.y_deci_mult as u128);
        let (opt_amt_x, opt_amt_y, opt_lp) = PieceSwapMath::get_add_liquidity_actual_amount(
            current_x,
            current_y,
        (pool.lp_amt as u128),
        (add_amt_x as u128) * (pool.x_deci_mult as u128),
        (add_amt_y as u128) * (pool.y_deci_mult as u128)
        );
        if (opt_lp == 0) {
            return (0,0,0)
        };

        let actual_add_x = ((opt_amt_x / (pool.x_deci_mult as u128)) as u64);
        let actual_add_y = ((opt_amt_y / (pool.y_deci_mult as u128)) as u64);

        // withdraw, merge, mint_to
        let x_coin = Coin::withdraw<X>(sender, actual_add_x);
        let y_coin = Coin::withdraw<Y>(sender, actual_add_y);
        Coin::merge(&mut pool.reserve_x, x_coin);
        Coin::merge(&mut pool.reserve_y, y_coin);
        mint_to(sender, (opt_lp as u64), pool);
        (actual_add_x, actual_add_y, (opt_lp as u64))
    }

    public fun add_liquidity_direct<X, Y>(
        coin_x: Coin::Coin<X>,
        coin_y: Coin::Coin<Y>,
    ): (Coin::Coin<X>, Coin::Coin<Y>, Coin::Coin<LPToken<X, Y>>) acquires PieceSwapPoolInfo {
        let add_amt_x = Coin::value(&coin_x);
        let add_amt_y = Coin::value(&coin_y);

        let pool = borrow_global_mut<PieceSwapPoolInfo<X, Y>>(MODULE_ADMIN);
        let current_x = (Coin::value(&pool.reserve_x) as u128) * (pool.x_deci_mult as u128);
        let current_y = (Coin::value(&pool.reserve_y) as u128) * (pool.y_deci_mult as u128);
        let (opt_amt_x, opt_amt_y, opt_lp) = PieceSwapMath::get_add_liquidity_actual_amount(
            current_x,
            current_y,
            (pool.lp_amt as u128),
            (add_amt_x as u128) * (pool.x_deci_mult as u128),
            (add_amt_y as u128) * (pool.y_deci_mult as u128)
        );
        if (opt_lp == 0) {
            return (coin_x, coin_y, Coin::zero<LPToken<X, Y>>())
        };

        let actual_add_x = ((opt_amt_x / (pool.x_deci_mult as u128)) as u64);
        let actual_add_y = ((opt_amt_y / (pool.y_deci_mult as u128)) as u64);

        let actual_add_x_coin = Coin::extract(&mut coin_x, actual_add_x);
        let actual_add_y_coin = Coin::extract(&mut coin_y, actual_add_y);
        Coin::merge(&mut pool.reserve_x, actual_add_x_coin);
        Coin::merge(&mut pool.reserve_y, actual_add_y_coin);
        let lp_coin = mint_direct((opt_lp as u64), pool);

        (coin_x, coin_y, lp_coin)
    }

    fun mint_to<X, Y>(to: &signer, amount: u64, pool: &mut PieceSwapPoolInfo<X, Y>) {
        let lp_coin = mint_direct(amount, pool);
        check_and_deposit(to, lp_coin);
    }

    fun mint_direct<X, Y>(amount: u64, pool: &mut PieceSwapPoolInfo<X, Y>): Coin::Coin<LPToken<X, Y>> {
        let lp_coin = Coin::mint(amount, &pool.lp_mint_cap);
        pool.lp_amt = pool.lp_amt + amount;
        lp_coin
    }

    public fun remove_liquidity<X, Y>(
        sender: &signer,
        remove_lp_amt: u64,
    ): (u64, u64) acquires PieceSwapPoolInfo {
        let pool = borrow_global_mut<PieceSwapPoolInfo<X, Y>>(MODULE_ADMIN);
        let current_x = (Coin::value(&pool.reserve_x) as u128) * (pool.x_deci_mult as u128);
        let current_y = (Coin::value(&pool.reserve_y) as u128) * (pool.y_deci_mult as u128);
        let (opt_amt_x, opt_amt_y) = PieceSwapMath::get_remove_liquidity_amounts(
            current_x,
            current_y,
          (pool.lp_amt as u128),
          (remove_lp_amt as u128),
        );

        let actual_remove_x = ((opt_amt_x / (pool.x_deci_mult as u128)) as u64);
        let actual_remove_y = ((opt_amt_y / (pool.y_deci_mult as u128)) as u64);

        // burn, split, and deposit
        burn_from(sender, remove_lp_amt, pool);
        let removed_x = Coin::extract(&mut pool.reserve_x, actual_remove_x);
        let removed_y = Coin::extract(&mut pool.reserve_y, actual_remove_y);

        check_and_deposit(sender, removed_x);
        check_and_deposit(sender, removed_y);

        (actual_remove_x, actual_remove_y)
    }

    public fun remove_liquidity_direct<X, Y>(
        remove_lp: Coin::Coin<LPToken<X, Y>>,
    ): (Coin::Coin<X>, Coin::Coin<Y>) acquires PieceSwapPoolInfo {
        let pool = borrow_global_mut<PieceSwapPoolInfo<X, Y>>(MODULE_ADMIN);
        let current_x = (Coin::value(&pool.reserve_x) as u128) * (pool.x_deci_mult as u128);
        let current_y = (Coin::value(&pool.reserve_y) as u128) * (pool.y_deci_mult as u128);
        let remove_lp_amt = Coin::value(&remove_lp);
        let (opt_amt_x, opt_amt_y) = PieceSwapMath::get_remove_liquidity_amounts(
            current_x,
            current_y,
            (pool.lp_amt as u128),
            (remove_lp_amt as u128),
        );

        let actual_remove_x = ((opt_amt_x / (pool.x_deci_mult as u128)) as u64);
        let actual_remove_y = ((opt_amt_y / (pool.y_deci_mult as u128)) as u64);

        // burn, split, and deposit
        burn_direct(remove_lp, pool);
        let removed_x = Coin::extract(&mut pool.reserve_x, actual_remove_x);
        let removed_y = Coin::extract(&mut pool.reserve_y, actual_remove_y);

        (removed_x, removed_y)
    }

    fun check_and_deposit<TokenType>(to: &signer, coin: Coin::Coin<TokenType>) {
        if(!Coin::is_account_registered<TokenType>(Signer::address_of(to))) {
            Coin::register_internal<TokenType>(to);
        };
        Coin::deposit(Signer::address_of(to), coin);
    }

    fun burn_from<X, Y>(from: &signer, amount: u64, pool: &mut PieceSwapPoolInfo<X, Y>) {
        let coin_to_burn = Coin::withdraw<LPToken<X, Y>>(from, amount);
        burn_direct(coin_to_burn, pool);
    }

    fun burn_direct<X, Y>(lp: Coin::Coin<LPToken<X, Y>>, pool: &mut PieceSwapPoolInfo<X, Y>) {
        let amount = Coin::value(&lp);
        Coin::burn(lp, &pool.lp_burn_cap);
        pool.lp_amt = pool.lp_amt - amount;
    }

    public fun swap_x_to_y<X, Y>(
        sender: &signer,
        amount_x_in: u64,
    ): u64 acquires PieceSwapPoolInfo {
        let coin_x = Coin::withdraw<X>(sender, amount_x_in);
        let coin_y = swap_x_to_y_direct<X, Y>(coin_x);
        let value_y = Coin::value(&coin_y);
        check_and_deposit(sender, coin_y);
        value_y
    }

    public fun swap_x_to_y_direct<X, Y>(
        coin_x: Coin::Coin<X>,
    ): Coin::Coin<Y> acquires PieceSwapPoolInfo {
        let pool = borrow_global_mut<PieceSwapPoolInfo<X, Y>>(MODULE_ADMIN);
        let current_x = (Coin::value(&pool.reserve_x) as u128) * (pool.x_deci_mult as u128);
        let current_y = (Coin::value(&pool.reserve_y) as u128) * (pool.y_deci_mult as u128);
        let x_value = (Coin::value(&coin_x) as u128);
        Coin::merge(&mut pool.reserve_x, coin_x);
        let input_x = x_value * (pool.x_deci_mult as u128);
        let opt_output_y = PieceSwapMath::get_swap_x_to_y_out(
            current_x,
            current_y,
            input_x,
            pool.K,
            pool.K2,
            pool.Xa,
            pool.Xb,
            pool.m,
            pool.n
        );

        let actual_out_y = ((opt_output_y / (pool.y_deci_mult as u128)) as u64);

        // handle fees
        let total_fees = actual_out_y * pool.swap_fee_per_million / 1000000;
        let protocol_fees = total_fees * pool.protocol_fee_share_per_thousand / 1000;
        let out_y_after_fees = actual_out_y - total_fees;
        let coin_y = Coin::extract(&mut pool.reserve_y, out_y_after_fees);
        let protocol_fee_y = Coin::extract<Y>(&mut pool.reserve_y, protocol_fees);
        Coin::merge(&mut pool.protocol_fee_y, protocol_fee_y);
        coin_y
    }

    public fun swap_y_to_x<X, Y>(
        sender: &signer,
        amount_y_in: u64,
    ): u64 acquires PieceSwapPoolInfo {
        let coin_y = Coin::withdraw<Y>(sender, amount_y_in);
        let coin_x = swap_y_to_x_direct<X, Y>(coin_y);
        let value_x = Coin::value(&coin_x);
        check_and_deposit(sender, coin_x);
        value_x
    }

    public fun swap_y_to_x_direct<X, Y>(
        coin_y: Coin::Coin<Y>,
    ): Coin::Coin<X> acquires PieceSwapPoolInfo {
        let pool = borrow_global_mut<PieceSwapPoolInfo<X, Y>>(MODULE_ADMIN);
        let current_x = (Coin::value(&pool.reserve_x) as u128) * (pool.x_deci_mult as u128);
        let current_y = (Coin::value(&pool.reserve_y) as u128) * (pool.y_deci_mult as u128);
        let y_value = (Coin::value(&coin_y) as u128);
        Coin::merge(&mut pool.reserve_y, coin_y);
        let input_y = y_value * (pool.y_deci_mult as u128);
        let opt_output_x = PieceSwapMath::get_swap_y_to_x_out(
            current_x,
            current_y,
            input_y,
            pool.K,
            pool.K2,
            pool.Xa,
            pool.Xb,
            pool.m,
            pool.n
        );

        let actual_out_x = ((opt_output_x / (pool.x_deci_mult as u128)) as u64);

        // handle fees
        let total_fees = actual_out_x * pool.swap_fee_per_million / 1000000;
        let protocol_fees = total_fees * pool.protocol_fee_share_per_thousand / 1000;
        let out_x_after_fees = actual_out_x - total_fees;
        let protocol_fee_x = Coin::extract<X>(&mut pool.reserve_x, protocol_fees);
        Coin::merge(&mut pool.protocol_fee_x, protocol_fee_x);
        let coin_x = Coin::extract(&mut pool.reserve_x, out_x_after_fees);
        coin_x
    }

    #[test_only]
    use HippoSwap::MockCoin;

    #[test_only]
    fun mock_init_pool<X, Y>(admin: &signer, lp_name: vector<u8>, lp_symbol: vector<u8>) {
        let billion = 1000000000;
        if (!Coin::is_coin_initialized<X>()) {
            MockCoin::initialize<X>(admin, 6);
        };
        if (!Coin::is_coin_initialized<Y>()) {
            MockCoin::initialize<Y>(admin, 6);
        };
        create_new_pool<X, Y>(
            admin,
            lp_name,
            lp_symbol,
            6,
            billion * billion, // we pretty much want k to be 10^18 in all cases
            110, // W1 = 1.10
            100,
            105, // W2 = 1.05
            100,
            100,
            100,
        );
    }


    #[test_only]
    fun mock_add_liquidity_direct_equal<X, Y>(amount: u64)
    : (Coin::Coin<X>, Coin::Coin<Y>, Coin::Coin<LPToken<X, Y>>) acquires PieceSwapPoolInfo {
        let coin_x = MockCoin::mint<X>(amount);
        let coin_y = MockCoin::mint<Y>(amount);
        add_liquidity_direct(coin_x, coin_y)
    }

    #[test_only]
    fun mock_init_pool_and_add_liquidity_direct<X, Y>(
        admin: &signer,
        lp_name: vector<u8>,
        lp_symbol: vector<u8>,
        initial_amt: u64
    ): Coin::Coin<LPToken<X, Y>> acquires PieceSwapPoolInfo {
        mock_init_pool<X, Y>(admin, lp_name, lp_symbol);
        // add liquidity
        let (remain_x, remain_y, lp) = mock_add_liquidity_direct_equal<X, Y>(initial_amt);
        assert!(Coin::value(&remain_x) == 0, 0);
        assert!(Coin::value(&remain_y) == 0, 0);
        assert!(Coin::value(&lp) == initial_amt, 0);
        Coin::destroy_zero(remain_x);
        Coin::destroy_zero(remain_y);
        lp
    }

    #[test_only]
    fun mock_init_pool_and_add_liquidity<X, Y>(
        admin: &signer,
        user: &signer,
        lp_name: vector<u8>,
        lp_symbol: vector<u8>,
        initial_amt: u64
    ): (u64, u64, u64) acquires PieceSwapPoolInfo {
        mock_init_pool<X, Y>(admin, lp_name, lp_symbol);
        // add liquidity
        MockCoin::faucet_mint_to<X>(user, initial_amt);
        MockCoin::faucet_mint_to<Y>(user, initial_amt);
        add_liquidity<X, Y>(user, initial_amt, initial_amt)
    }

    #[test(admin=@HippoSwap, user=@0x12345)]
    fun test_create_pool_with_liquidity(admin: &signer, user: &signer) acquires PieceSwapPoolInfo {
        let lp = mock_init_pool_and_add_liquidity_direct<MockCoin::WUSDT, MockCoin::WUSDC>(
            admin,
            b"USDT-USDC LP for PieceSwap",
            b"USDT-USDC LP(PieceSwap)",
            100000
        );
        check_and_deposit(user, lp);
    }

    #[test(admin=@HippoSwap, user=@0x12345)]
    fun test_create_pool_with_liquidity_then_remove(admin: &signer, user: &signer) acquires PieceSwapPoolInfo {
        let amt = 1000000;
        let lp = mock_init_pool_and_add_liquidity_direct<MockCoin::WUSDT, MockCoin::WUSDC>(
            admin,
            b"USDT-USDC LP for PieceSwap",
            b"USDT-USDC LP(PieceSwap)",
            amt
        );
        let (coin_x, coin_y) = remove_liquidity_direct(lp);
        assert!(Coin::value(&coin_x) == amt, 0);
        assert!(Coin::value(&coin_y) == amt, 0);
        check_and_deposit(user, coin_x);
        check_and_deposit(user, coin_y);
    }

    #[test(admin=@HippoSwap, user=@0x12345)]
    fun test_remove_liquidity(admin: &signer, user: &signer) acquires PieceSwapPoolInfo {
        let amt = 1000000;
        let lp = mock_init_pool_and_add_liquidity_direct<MockCoin::WUSDT, MockCoin::WUSDC>(
            admin,
            b"USDT-USDC LP for PieceSwap",
            b"USDT-USDC LP(PieceSwap)",
            amt
        );
        check_and_deposit(user, lp);
        let (amt_x, amt_y) = remove_liquidity<MockCoin::WUSDT, MockCoin::WUSDC>(user, amt);
        let user_addr = Signer::address_of(user);
        assert!(Coin::balance<MockCoin::WUSDT>(user_addr) == amt_x, 0);
        assert!(Coin::balance<MockCoin::WUSDC>(user_addr) == amt_y, 0);
        assert!(amt == amt_x, 0);
        assert!(amt == amt_y, 0);
        assert!(Coin::balance<LPToken<MockCoin::WUSDT, MockCoin::WUSDC>>(user_addr) == 0, 0);
    }

    #[test(admin=@HippoSwap, user=@0x12345)]
    fun test_add_liquidity(admin: &signer, user: &signer) acquires PieceSwapPoolInfo {
        let amt = 1000000;
        let (added_x, added_y, lp_amt) = mock_init_pool_and_add_liquidity<MockCoin::WUSDT, MockCoin::WUSDC>(
            admin,
            user,
            b"USDT-USDC LP for PieceSwap",
            b"USDT-USDC LP(PieceSwap)",
            amt
        );
        assert!(added_x == amt, 0);
        assert!(added_y == amt, 0);
        assert!(lp_amt == amt, 0);
    }

    #[test(admin=@HippoSwap, user=@0x12345)]
    #[expected_failure]
    fun test_add_initial_liquidity_unequal(admin: &signer, user: &signer) acquires PieceSwapPoolInfo {
        mock_init_pool<MockCoin::WUSDT, MockCoin::WUSDC>(
            admin,
            b"USDT-USDC LP for PieceSwap",
            b"USDT-USDC LP(PieceSwap)",
        );
        let coin_x = MockCoin::mint<MockCoin::WUSDT>(100000);
        let coin_y = MockCoin::mint<MockCoin::WUSDC>(10000);
        let (remain_x, remain_y, lp) = add_liquidity_direct(coin_x, coin_y);
        check_and_deposit(user, remain_x);
        check_and_deposit(user, remain_y);
        check_and_deposit(user, lp);
    }

    #[test_only]
    fun test_swap_x_to_y_parameterized(
        admin: &signer,
        user: &signer,
        multiplier: u64,
        swap_amt: u64,
        liquidity_amt: u64,
    ) acquires PieceSwapPoolInfo {
        let amt = liquidity_amt * multiplier;
        mock_init_pool_and_add_liquidity<MockCoin::WUSDT, MockCoin::WUSDC>(
            admin,
            user,
            b"USDT-USDC LP for PieceSwap",
            b"USDT-USDC LP(PieceSwap)",
            amt
        );
        let user_addr = Signer::address_of(user);
        swap_amt = swap_amt * multiplier;
        MockCoin::faucet_mint_to<MockCoin::WUSDT>(user, swap_amt);
        swap_x_to_y<MockCoin::WUSDT, MockCoin::WUSDC>(user, swap_amt);
        assert!(Coin::balance<MockCoin::WUSDT>(user_addr) == 0, 0);
        assert!(Coin::balance<MockCoin::WUSDC>(user_addr) != 0, 0);
        // check fees
        let pool = borrow_global<PieceSwapPoolInfo<MockCoin::WUSDT, MockCoin::WUSDC>>(Signer::address_of(admin));
        assert!(Coin::value(&pool.protocol_fee_x) == 0, 0);
        assert!(Coin::value(&pool.protocol_fee_y) > 0, 0);
    }

    #[test(admin=@HippoSwap, user=@0x12345)]
    fun test_swap_x_to_y(admin: &signer, user: &signer) acquires PieceSwapPoolInfo {
        let multiplier = 1000000;
        let swap_amt = 1;
        let liquidity_amt = 100000000;
        test_swap_x_to_y_parameterized(admin, user, multiplier, swap_amt, liquidity_amt);
        let user_addr = Signer::address_of(user);
        assert!(Coin::balance<MockCoin::WUSDC>(user_addr) > swap_amt * multiplier * 999 / 1000, 0);
        assert!(Coin::balance<MockCoin::WUSDC>(user_addr) < swap_amt * multiplier * 1001 / 1000, 0);

        let pool = borrow_global<PieceSwapPoolInfo<MockCoin::WUSDT, MockCoin::WUSDC>>(Signer::address_of(admin));
        assert!(
            Coin::balance<MockCoin::WUSDC>(user_addr) +
            Coin::value(&pool.reserve_y) +
            Coin::value(&pool.protocol_fee_y) == liquidity_amt * multiplier,
            0
        );
    }

    #[test_only]
    fun test_swap_y_to_x_parameterized(
        admin: &signer,
        user: &signer,
        multiplier: u64,
        swap_amt: u64,
        liquidity_amt: u64,
    ) acquires PieceSwapPoolInfo {
        let amt = liquidity_amt * multiplier;
        mock_init_pool_and_add_liquidity<MockCoin::WUSDT, MockCoin::WUSDC>(
            admin,
            user,
            b"USDT-USDC LP for PieceSwap",
            b"USDT-USDC LP(PieceSwap)",
            amt
        );
        let user_addr = Signer::address_of(user);
        swap_amt = swap_amt * multiplier;
        MockCoin::faucet_mint_to<MockCoin::WUSDC>(user, swap_amt);
        swap_y_to_x<MockCoin::WUSDT, MockCoin::WUSDC>(user, swap_amt);
        assert!(Coin::balance<MockCoin::WUSDC>(user_addr) == 0, 0);
        assert!(Coin::balance<MockCoin::WUSDT>(user_addr) > 0, 0);
        // check fees
        let pool = borrow_global<PieceSwapPoolInfo<MockCoin::WUSDT, MockCoin::WUSDC>>(Signer::address_of(admin));
        assert!(Coin::value(&pool.protocol_fee_x) > 0, 0);
        assert!(Coin::value(&pool.protocol_fee_y) == 0, 0);
    }

    #[test(admin=@HippoSwap, user=@0x12345)]
    fun test_swap_y_to_x(admin: &signer, user: &signer) acquires PieceSwapPoolInfo {
        let multiplier = 1000000;
        let swap_amt = 1;
        let liquidity_amt = 100000000;
        test_swap_y_to_x_parameterized(admin, user, multiplier, swap_amt, liquidity_amt);
        let user_addr = Signer::address_of(user);
        assert!(Coin::balance<MockCoin::WUSDT>(user_addr) > swap_amt * multiplier * 999 / 1000, 0);
        assert!(Coin::balance<MockCoin::WUSDT>(user_addr) < swap_amt * multiplier* 1001 / 1000, 0);

        let pool = borrow_global<PieceSwapPoolInfo<MockCoin::WUSDT, MockCoin::WUSDC>>(Signer::address_of(admin));
        assert!(
            Coin::balance<MockCoin::WUSDT>(user_addr) +
            Coin::value(&pool.reserve_x) +
            Coin::value(&pool.protocol_fee_x) == liquidity_amt * multiplier,
            0
        );
    }


    #[test_only]
    public fun get_reserve_amounts<X, Y>(): (u64, u64) acquires PieceSwapPoolInfo {
        let i = borrow_global<PieceSwapPoolInfo<X, Y>>(MODULE_ADMIN);
        return (Coin::value(&i.reserve_x), Coin::value(&i.reserve_y))
    }

    #[test_only]
    public fun get_fee_amounts<X, Y>(): (u64, u64) acquires PieceSwapPoolInfo {
        let i = borrow_global<PieceSwapPoolInfo<X, Y>>(MODULE_ADMIN);
        return (Coin::value(&i.protocol_fee_x), Coin::value(&i.protocol_fee_y))
    }
}
}
