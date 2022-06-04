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
    const ERROR_NOT_CREATOR: u64 = 2;

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
    }

    public fun create_token_pair<X, Y>(
        admin: &signer,
        lp_name: vector<u8>,
        lp_symbol: vector<u8>,
        k: u128,
        w1_numerator: u128,
        w1_denominator: u128,
        w2_numerator: u128,
        w2_denominator: u128,
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

        // 3. initialize LP
        let (lp_mint_cap, lp_burn_cap) = Coin::initialize<LPToken<X,Y>>(
            admin,
            ASCII::string(lp_name),
            ASCII::string(lp_symbol),
            8,
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

    fun mint_to<X, Y>(to: &signer, amount: u64, pool: &mut PieceSwapPoolInfo<X, Y>) {
        let lp_coin = Coin::mint(amount, &pool.lp_mint_cap);
        pool.lp_amt =  pool.lp_amt + amount;
        check_and_deposit(to, lp_coin);
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

    fun check_and_deposit<TokenType>(to: &signer, coin: Coin::Coin<TokenType>) {
        if(!Coin::is_account_registered<TokenType>(Signer::address_of(to))) {
            Coin::register_internal<TokenType>(to);
        };
        Coin::deposit(Signer::address_of(to), coin);
    }

    fun burn_from<X, Y>(from: &signer, amount: u64, pool: &mut PieceSwapPoolInfo<X, Y>) {
        let coin_to_burn = Coin::withdraw<LPToken<X, Y>>(from, amount);
        Coin::burn(coin_to_burn, &pool.lp_burn_cap);
        pool.lp_amt = pool.lp_amt - amount;
    }

    public fun swap_x_to_y<X, Y>(
        sender: &signer,
        amount_x_in: u64,
    ): u64 acquires PieceSwapPoolInfo {
        let pool = borrow_global_mut<PieceSwapPoolInfo<X, Y>>(MODULE_ADMIN);
        let current_x = (Coin::value(&pool.reserve_x) as u128) * (pool.x_deci_mult as u128);
        let current_y = (Coin::value(&pool.reserve_y) as u128) * (pool.y_deci_mult as u128);
        let input_x = (amount_x_in as u128) * (pool.x_deci_mult as u128);
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
        let coin_y = Coin::extract(&mut pool.reserve_y, actual_out_y);
        check_and_deposit(sender, coin_y);
        actual_out_y
    }

    public fun swap_y_to_x<X, Y>(
        sender: &signer,
        amount_y_in: u64,
    ): u64 acquires PieceSwapPoolInfo {
        let pool = borrow_global_mut<PieceSwapPoolInfo<X, Y>>(MODULE_ADMIN);
        let current_x = (Coin::value(&pool.reserve_x) as u128) * (pool.x_deci_mult as u128);
        let current_y = (Coin::value(&pool.reserve_y) as u128) * (pool.y_deci_mult as u128);
        let input_y = (amount_y_in as u128) * (pool.y_deci_mult as u128);
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
        let coin_x = Coin::extract(&mut pool.reserve_x, actual_out_x);
        check_and_deposit(sender, coin_x);
        actual_out_x
    }
}
}
