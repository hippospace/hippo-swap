/// Uniswap v2 like token swap program
module HippoSwap::CPSwap {
    use Std::Signer;
    use Std::Option;
    use Std::ASCII;

    use AptosFramework::Coin;
    use AptosFramework::Timestamp;

    use HippoSwap::SafeMath;
    use HippoSwap::Utils;
    use HippoSwap::Math;
    use HippoSwap::CPSwapUtils;

    const MODULE_ADMIN: address = @HippoSwap;
    const MINIMUM_LIQUIDITY: u128 = 1000;
    const BALANCE_MAX: u128 = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF; // 2**112

    // List of errors
    const ERROR_ONLY_ADMIN: u64 = 0;
    const ERROR_ALREADY_INITIALIZED: u64 = 1;
    const ERROR_NOT_CREATOR: u64 = 2;
    const ERROR_ALREADY_LOCKED: u64 = 3;
    const ERROR_INSUFFICIENT_LIQUIDITY_MINTED: u64 = 4;
    const ERROR_OVERFLOW: u64 = 5;
    const ERROR_INSUFFICIENT_AMOUNT: u64 = 6;
    const ERROR_INSUFFICIENT_LIQUIDITY: u64 = 7;
    const ERROR_INVALID_AMOUNT: u64 = 8;
    const ERROR_TOKENS_NOT_SORTED: u64 = 9;
    const ERROR_INSUFFICIENT_LIQUIDITY_BURNED: u64 = 10;
    const ERROR_INSUFFICIENT_TOKEN0_AMOUNT: u64 = 11;
    const ERROR_INSUFFICIENT_TOKEN1_AMOUNT: u64 = 12;
    const ERROR_INSUFFICIENT_OUTPUT_AMOUNT: u64 = 13;
    const ERROR_INSUFFICIENT_INPUT_AMOUNT: u64 = 14;
    const ERROR_K: u64 = 15;
    const ERROR_X_NOT_REGISTERED: u64 = 16;
    const ERROR_Y_NOT_REGISTERED: u64 = 16;

    /// The LP Token type
    struct LPToken<phantom X, phantom Y> has key {}

    /// Stores the metadata required for the token pairs
    struct TokenPairMetadata<phantom X, phantom Y> has key {
        /// Lock for mint and burn
        locked: bool,
        /// The admin of the token pair
        creator: address,
        /// The address to transfer mint fees to
        fee_to: address,
        /// Whether we are charging a fee for mint/burn
        fee_on: bool,
        /// It's reserve_x * reserve_y, as of immediately after the most recent liquidity event
        k_last: u128,
        /// The LP token
        lp: Coin::Coin<LPToken<X, Y>>,
        /// T0 token balance
        balance_x: Coin::Coin<X>,
        /// T1 token balance
        balance_y: Coin::Coin<Y>,
        /// Mint capacity of LP Token
        mint_cap: Coin::MintCapability<LPToken<X, Y>>,
        /// Burn capacity of LP Token
        burn_cap: Coin::BurnCapability<LPToken<X, Y>>,
    }

    /// Stores the reservation info required for the token pairs
    struct TokenPairReserve<phantom X, phantom Y> has key {
        reserve_x: u64,
        reserve_y: u64,
        block_timestamp_last: u64
    }

    // ================= Init functions ========================
    /// Create the specified token pair
    public fun create_token_pair<X, Y>(
        admin: &signer,
        fee_to: address,
        fee_on: bool,
        lp_name: vector<u8>,
        lp_symbol: vector<u8>
    ) {
        let sender_addr = Signer::address_of(admin);
        assert!(sender_addr == MODULE_ADMIN, ERROR_NOT_CREATOR);

        assert!(!exists<TokenPairReserve<X, Y>>(sender_addr), ERROR_ALREADY_INITIALIZED);
        assert!(!exists<TokenPairReserve<Y, X>>(sender_addr), ERROR_ALREADY_INITIALIZED);

        // now we init the LP token
        let (mint_cap, burn_cap) = Coin::initialize<LPToken<X, Y>>(
            admin,
            ASCII::string(lp_name),
            ASCII::string(lp_symbol),
            8,
            true
        );

        move_to<TokenPairReserve<X, Y>>(
            admin,
            TokenPairReserve {
                reserve_x: 0,
                reserve_y: 0,
                block_timestamp_last: 0
            }
        );

        move_to<TokenPairMetadata<X, Y>>(
            admin,
            TokenPairMetadata {
                locked: false,
                creator: sender_addr,
                fee_to,
                fee_on,
                k_last: 0,
                lp: Coin::zero<LPToken<X, Y>>(),
                balance_x: Coin::zero<X>(),
                balance_y: Coin::zero<Y>(),
                mint_cap,
                burn_cap
            }
        );

        // create LP CoinStore for admin, which is needed as a lock for minimum_liquidity
        Coin::register_internal<LPToken<X,Y>>(admin);
    }

    /// The init process for a sender. One must call this function first
    /// before interacting with the mint/burn.
    public fun register_account<X, Y>(sender: &signer) {
        Coin::register_internal<LPToken<X, Y>>(sender);
    }

    // ====================== Getters ===========================
    /// Get the current reserves of T0 and T1 with the latest updated timestamp
    public fun get_reserves<X, Y>(): (u64, u64, u64) acquires TokenPairReserve {
        let reserve = borrow_global<TokenPairReserve<X, Y>>(MODULE_ADMIN);
        (
            reserve.reserve_x,
            reserve.reserve_y,
            reserve.block_timestamp_last
        )
    }

    /// Obtain the LP token balance of `addr`.
    /// This method can only be used to check other users' balance.
    public fun lp_balance<X, Y>(addr: address): u64 {
        Coin::balance<LPToken<X, Y>>(addr)
    }

    /// The amount of balance currently in pools of the liquidity pair
    public fun token_balances<X, Y>(): (u64, u64) acquires TokenPairMetadata {
        let meta =
            borrow_global<TokenPairMetadata<X, Y>>(MODULE_ADMIN);
        token_balances_metadata<X, Y>(meta)
    }

    // ===================== Update functions ======================
    /// Add more liquidity to token types. This method explicitly assumes the
    /// min of both tokens are 0.
    public fun add_liquidity<X, Y>(
        sender: &signer,
        amount_x: u64,
        amount_y: u64
    ): (u64, u64, u64) acquires TokenPairReserve, TokenPairMetadata {
        let (reserve_x, reserve_y, _) = get_reserves<X, Y>();
        let (a_x, a_y) = if (reserve_x == 0 && reserve_y == 0) {
            (amount_x, amount_y)
        } else {
            let amount_y_optimal = CPSwapUtils::quote(amount_x, reserve_x, reserve_y);
            if (amount_y_optimal <= amount_y) {
                (amount_x, amount_y_optimal)
            } else {
                let amount_x_optimal = CPSwapUtils::quote(amount_y, reserve_y, reserve_x);
                assert!(amount_x_optimal <= amount_x, ERROR_INVALID_AMOUNT);
                (amount_x_optimal, amount_y)
            }
        };

        deposit_x<X, Y>(Coin::withdraw<X>(sender, a_x));
        deposit_y<X, Y>(Coin::withdraw<Y>(sender, a_y));

        let lp = mint<X, Y>();
        let lp_amount = Coin::value(&lp);
        Coin::deposit(Signer::address_of(sender), lp);

        (a_x, a_y, lp_amount)
    }

    /// Add more liquidity to token types. This method explicitly assumes the
    /// min of both tokens are 0.
    public fun add_liquidity_direct<X, Y>(
        x: Coin::Coin<X>,
        y: Coin::Coin<Y>,
    ): (Coin::Coin<X>, Coin::Coin<Y>, Coin::Coin<LPToken<X, Y>>) acquires TokenPairReserve, TokenPairMetadata {
        let amount_x = Coin::value(&x);
        let amount_y = Coin::value(&y);
        let (reserve_x, reserve_y, _) = get_reserves<X, Y>();
        let (a_x, a_y) = if (reserve_x == 0 && reserve_y == 0) {
            (amount_x, amount_y)
        } else {
            let amount_y_optimal = CPSwapUtils::quote(amount_x, reserve_x, reserve_y);
            if (amount_y_optimal <= amount_y) {
                (amount_x, amount_y_optimal)
            } else {
                let amount_x_optimal = CPSwapUtils::quote(amount_y, reserve_y, reserve_x);
                assert!(amount_x_optimal <= amount_x, ERROR_INVALID_AMOUNT);
                (amount_x_optimal, amount_y)
            }
        };

        assert!(a_x <= amount_x, ERROR_INSUFFICIENT_AMOUNT);
        assert!(a_y <= amount_y, ERROR_INSUFFICIENT_AMOUNT);

        let left_x = Coin::extract(&mut x, amount_x - a_x);
        let left_y = Coin::extract(&mut y, amount_y - a_y);
        deposit_x<X, Y>(x);
        deposit_y<X, Y>(y);

        (left_x, left_y, mint<X, Y>())
    }

    /// Remove liquidity to token types.
    public fun remove_liquidity<X, Y>(
        sender: &signer,
        liquidity: u64,
        amount_x_min: u64,
        amount_y_min: u64
    ): (u64, u64) acquires TokenPairMetadata, TokenPairReserve {
        let coins = Coin::withdraw<LPToken<X, Y>>(sender, liquidity);
        let (coins_x, coins_y) = remove_liquidity_direct<X, Y>(coins, amount_x_min, amount_y_min);

        let amount_x = Coin::value(&coins_x);
        let amount_y = Coin::value(&coins_y);

        Coin::deposit<X>(Signer::address_of(sender), coins_x);
        Coin::deposit<Y>(Signer::address_of(sender), coins_y);

        (amount_x, amount_y)
    }

    /// Remove liquidity to token types.
    public fun remove_liquidity_direct<X, Y>(
        liquidity: Coin::Coin<LPToken<X, Y>>,
        amount_x_min: u64,
        amount_y_min: u64
    ): (Coin::Coin<X>, Coin::Coin<Y>) acquires TokenPairMetadata, TokenPairReserve {
        tranfer_lp_coin_in<X, Y>(liquidity);

        let (coins_x, coins_y) = burn<X, Y>();
        assert!(Coin::value(&coins_x) >= amount_x_min, ERROR_INSUFFICIENT_TOKEN0_AMOUNT);
        assert!(Coin::value(&coins_y) >= amount_y_min, ERROR_INSUFFICIENT_TOKEN1_AMOUNT);

        (coins_x, coins_y)
    }

    /// Swap X to Y, X is in and Y is out. This method assumes amount_out_min is 0
    public fun swap_x_to_exact_y<X, Y>(
        sender: &signer,
        amount_in: u64,
        to: address
    ): u64 acquires TokenPairReserve, TokenPairMetadata {
        let coins = Coin::withdraw<X>(sender, amount_in);
        let (coins_x_out, coins_y_out) = swap_x_to_exact_y_direct<X, Y>(coins);
        let amount_out = Coin::value(&coins_y_out);
        Coin::deposit(to, coins_x_out); // or others ways to drop `coins_x_out`
        Coin::deposit(to, coins_y_out);
        amount_out
    }

    /// Swap X to Y, X is in and Y is out. This method assumes amount_out_min is 0
    public fun swap_x_to_exact_y_direct<X, Y>(
        coins_in: Coin::Coin<X>
    ): (Coin::Coin<X>, Coin::Coin<Y>) acquires TokenPairReserve, TokenPairMetadata {
        let amount_in = Coin::value<X>(&coins_in);
        deposit_x<X, Y>(coins_in);
        let (rin, rout, _) = get_reserves<X, Y>();
        let amount_out = CPSwapUtils::get_amount_out(amount_in, rin, rout);
        let (coins_x_out, coins_y_out) = swap<X, Y>(0, amount_out);
        assert!(Coin::value<X>(&coins_x_out) == 0, ERROR_INSUFFICIENT_OUTPUT_AMOUNT);
        (coins_x_out, coins_y_out)
    }

    /// Swap Y to X, Y is in and X is out. This method assumes amount_out_min is 0
    public fun swap_y_to_exact_x<X, Y>(
        sender: &signer,
        amount_in: u64,
        to: address
    ): u64 acquires TokenPairReserve, TokenPairMetadata {
        let coins = Coin::withdraw<Y>(sender, amount_in);
        let (coins_x_out, coins_y_out) = swap_y_to_exact_x_direct<X, Y>(coins);
        let amount_out = Coin::value<X>(&coins_x_out);
        Coin::deposit(to, coins_x_out);
        Coin::deposit(to, coins_y_out); // or others ways to drop `coins_y_out`
        amount_out
    }

    /// Swap Y to X, Y is in and X is out. This method assumes amount_out_min is 0
    public fun swap_y_to_exact_x_direct<X, Y>(
        coins_in: Coin::Coin<Y>
    ): (Coin::Coin<X>, Coin::Coin<Y>) acquires TokenPairReserve, TokenPairMetadata {
        let amount_in = Coin::value<Y>(&coins_in);
        deposit_y<X, Y>(coins_in);
        let (rin, rout, _) = get_reserves<X, Y>();
        let amount_out = CPSwapUtils::get_amount_out(amount_in, rin, rout);
        let (coins_x_out, coins_y_out) = swap<X, Y>(amount_out, 0);
        assert!(Coin::value<Y>(&coins_y_out) == 0, ERROR_INSUFFICIENT_OUTPUT_AMOUNT);
        (coins_x_out, coins_y_out)
    }

    // ======================= Internal Functions ==============================
    fun swap<X, Y>(
        amount_x_out: u64,
        amount_y_out: u64
    ): (Coin::Coin<X>, Coin::Coin<Y>) acquires TokenPairReserve, TokenPairMetadata {
        assert!(Utils::is_tokens_sorted<X, Y>(), ERROR_TOKENS_NOT_SORTED);
        assert!(amount_x_out > 0 || amount_y_out > 0, ERROR_INSUFFICIENT_OUTPUT_AMOUNT);

        let reserves = borrow_global_mut<TokenPairReserve<X, Y>>(MODULE_ADMIN);
        assert!(amount_x_out < reserves.reserve_x && amount_y_out < reserves.reserve_y, ERROR_INSUFFICIENT_LIQUIDITY);

        let metadata = borrow_global_mut<TokenPairMetadata<X, Y>>(MODULE_ADMIN);

        // Lock it, reentrancy protection
        assert!(!metadata.locked, ERROR_ALREADY_LOCKED);
        metadata.locked = true;

        // TODO: this required? `require(to != X && to != Y, 'UniswapV2: INVALID_TO')`
        let coins_x_out = Coin::zero<X>();
        let coins_y_out = Coin::zero<Y>();
        if (amount_x_out > 0) Coin::merge(&mut coins_x_out, extract_x(amount_x_out, metadata));
        if (amount_y_out > 0) Coin::merge(&mut coins_y_out, extract_y(amount_y_out, metadata));
        let (balance_x, balance_y) = token_balances_metadata<X, Y>(metadata);

        let amount_x_in = if (balance_x > reserves.reserve_x - amount_x_out) {
            balance_x - (reserves.reserve_x - amount_x_out)
        } else { 0 };
        let amount_y_in = if (balance_y > reserves.reserve_y - amount_y_out) {
            balance_y - (reserves.reserve_y - amount_y_out)
        } else { 0 };

        assert!(amount_x_in > 0 || amount_y_in > 0, ERROR_INSUFFICIENT_INPUT_AMOUNT);
        let balance_x_adjusted = SafeMath::sub(
            SafeMath::mul((balance_x as u128), 1000),
            SafeMath::mul((amount_x_in as u128), 3)
        );
        let balance_y_adjusted = SafeMath::sub(
            SafeMath::mul((balance_y as u128), 1000),
            SafeMath::mul((amount_y_in as u128), 3)
        );

        let k = SafeMath::mul(
            1000000,
            SafeMath::mul((reserves.reserve_x as u128), (reserves.reserve_y as u128))
        );
        assert!(SafeMath::mul(balance_x_adjusted, balance_y_adjusted) >= k, ERROR_K);

        update(balance_x, balance_y, reserves);

        metadata.locked = false;

        (coins_x_out, coins_y_out)
    }

    /// Mint LP Token.
    /// This low-level function should be called from a contract which performs important safety checks
    fun mint<X, Y>(): Coin::Coin<LPToken<X, Y>> acquires TokenPairReserve, TokenPairMetadata {
        let metadata = borrow_global_mut<TokenPairMetadata<X, Y>>(MODULE_ADMIN);

        // Lock it, reentrancy protection
        assert!(!metadata.locked, ERROR_ALREADY_LOCKED);
        metadata.locked = true;

        let reserves = borrow_global_mut<TokenPairReserve<X, Y>>(MODULE_ADMIN);
        let (balance_x, balance_y) = token_balances_metadata<X, Y>(metadata);
        let amount_x = SafeMath::sub((balance_x as u128), (reserves.reserve_x as u128));
        let amount_y = SafeMath::sub((balance_y as u128), (reserves.reserve_y as u128));

        mint_fee(reserves.reserve_x, reserves.reserve_y, metadata);

        let total_supply = (total_lp_supply<X, Y>() as u128);
        let liquidity = if (total_supply == 0u128) {
            let l = SafeMath::sub(
                Math::sqrt(
                    SafeMath::mul(amount_x, amount_y)
                ),
                MINIMUM_LIQUIDITY
            );
            // permanently lock the first MINIMUM_LIQUIDITY tokens
            mint_lp_to<X, Y>(MODULE_ADMIN, (MINIMUM_LIQUIDITY as u64), &metadata.mint_cap);
            l
        } else {
            Math::min(
                SafeMath::div(
                    SafeMath::mul(amount_x, total_supply),
                    (reserves.reserve_x as u128)
                ),
                SafeMath::div(
                    SafeMath::mul(amount_y, total_supply),
                    (reserves.reserve_y as u128)
                )
            )
        };

        assert!(liquidity > 0u128, ERROR_INSUFFICIENT_LIQUIDITY_MINTED);
//        mint_lp_to<X, Y>(
//            Signer::address_of(sender),
//            (liquidity as u64),
//            &metadata.mint_cap
//        );
        let lp = mint_lp<X, Y>((liquidity as u64), &metadata.mint_cap);

        update<X, Y>(balance_x, balance_y, reserves);

        if (metadata.fee_on)
            metadata.k_last = SafeMath::mul((reserves.reserve_x as u128), (reserves.reserve_y as u128));

        // Unlock it
        metadata.locked = false;

        lp
    }

    fun burn<X, Y>(): (Coin::Coin<X>, Coin::Coin<Y>) acquires TokenPairMetadata, TokenPairReserve {
        let metadata = borrow_global_mut<TokenPairMetadata<X, Y>>(MODULE_ADMIN);

        // Lock it, reentrancy protection
        assert!(!metadata.locked, ERROR_ALREADY_LOCKED);
        metadata.locked = true;

        let reserves = borrow_global_mut<TokenPairReserve<X, Y>>(MODULE_ADMIN);
        let (balance_x, balance_y) = token_balances_metadata<X, Y>(metadata);
        let liquidity = Coin::value(&metadata.lp);

        mint_fee<X, Y>(reserves.reserve_x, reserves.reserve_y, metadata);

        let total_lp_supply = total_lp_supply<X, Y>();
        let amount_x = (SafeMath::div(
            SafeMath::mul(
                (balance_x as u128),
                (liquidity as u128)
            ),
        (total_lp_supply as u128)
        ) as u64);
        let amount_y = (SafeMath::div(
            SafeMath::mul(
                (balance_y as u128),
                (liquidity as u128)
            ),
        (total_lp_supply as u128)
        ) as u64);
        assert!(amount_x > 0 && amount_y > 0, ERROR_INSUFFICIENT_LIQUIDITY_BURNED);

        burn_lp<X, Y>(liquidity, metadata);

        let w_x = extract_x(amount_x, metadata);
        let w_y = extract_y(amount_y, metadata);

        let (balance_x, balance_y) = token_balances_metadata<X, Y>(metadata);
        update(balance_x,balance_y, reserves);

        if (metadata.fee_on)
            metadata.k_last = SafeMath::mul((reserves.reserve_x as u128), (reserves.reserve_y as u128));

        metadata.locked = false;

        (w_x, w_y)
    }

    fun update<X, Y>(balance_x: u64, balance_y: u64, reserve: &mut TokenPairReserve<X, Y>) {
        assert!(
            (balance_x as u128) <= BALANCE_MAX && (balance_y as u128) <= BALANCE_MAX,
            ERROR_OVERFLOW
        );

        let block_timestamp = Timestamp::now_seconds() % 0xFFFFFFFF;
        // TODO
        // let time_elapsed = block_timestamp - timestamp_last; // overflow is desired
        // if (time_elapsed > 0 && reserve_x != 0 && reserve_y != 0) {
        //      price0CumulativeLast += uint(UQ112x112.encode(_reserve_y).uqdiv(_reserve_x)) * timeElapsed;
        //      price1CumulativeLast += uint(UQ112x112.encode(_reserve_x).uqdiv(_reserve_y)) * timeElapsed;
        //  }

        reserve.reserve_x = balance_x;
        reserve.reserve_y = balance_y;
        reserve.block_timestamp_last = block_timestamp;
    }

    fun token_balances_metadata<X, Y>(metadata: &TokenPairMetadata<X, Y>): (u64, u64) {
        (
            Coin::value(&metadata.balance_x),
            Coin::value(&metadata.balance_y)
        )
    }

    /// Get the total supply of LP Tokens
    fun total_lp_supply<X, Y>(): u64 {
        Option::get_with_default(
            &Coin::supply<LPToken<X, Y>>(),
            0u64
        )
    }

    /// Mint LP Tokens to account
    fun mint_lp_to<X, Y>(
        to: address,
        amount: u64,
        mint_cap: &Coin::MintCapability<LPToken<X, Y>>
    ) {
        let coins = Coin::mint<LPToken<X, Y>>(amount, mint_cap);
        Coin::deposit(to, coins);
    }

    /// Mint LP Tokens to account
    fun mint_lp<X, Y>(amount: u64, mint_cap: &Coin::MintCapability<LPToken<X, Y>>): Coin::Coin<LPToken<X, Y>> {
        Coin::mint<LPToken<X, Y>>(amount, mint_cap)
    }

    /// Burn LP tokens held in this contract, i.e. TokenPairMetadata.lp
    fun burn_lp<X, Y>(
        amount: u64,
        metadata: &mut TokenPairMetadata<X, Y>
    ) {
        assert!(Coin::value(&metadata.lp) >= amount, ERROR_INSUFFICIENT_LIQUIDITY);
        let coins = Coin::extract(&mut metadata.lp, amount);
        Coin::burn<LPToken<X, Y>>(coins, &metadata.burn_cap);
    }

    /// Transfer LP Tokens to swap contract
    fun tranfer_lp_coin_in<X, Y>(coins: Coin::Coin<LPToken<X, Y>>) acquires TokenPairMetadata {
        let metadata = borrow_global_mut<TokenPairMetadata<X, Y>>(@HippoSwap);
        Coin::merge(&mut metadata.lp, coins);
    }

    fun deposit_x<X, Y>(amount: Coin::Coin<X>) acquires TokenPairMetadata {
        let metadata =
            borrow_global_mut<TokenPairMetadata<X, Y>>(MODULE_ADMIN);
        Coin::merge(&mut metadata.balance_x, amount);
    }

    fun deposit_y<X, Y>(amount: Coin::Coin<Y>) acquires TokenPairMetadata {
        let metadata =
            borrow_global_mut<TokenPairMetadata<X, Y>>(MODULE_ADMIN);
        Coin::merge(&mut metadata.balance_y, amount);
    }

    /// Extract `amount` from this contract
    fun extract_x<X, Y>(amount: u64, metadata: &mut TokenPairMetadata<X, Y>): Coin::Coin<X> {
        assert!(Coin::value<X>(&metadata.balance_x) > amount, ERROR_INSUFFICIENT_AMOUNT);
        Coin::extract(&mut metadata.balance_x, amount)
    }

    /// Extract `amount` from this contract
    fun extract_y<X, Y>(amount: u64, metadata: &mut TokenPairMetadata<X, Y>): Coin::Coin<Y> {
        assert!(Coin::value<Y>(&metadata.balance_y) > amount, ERROR_INSUFFICIENT_AMOUNT);
        Coin::extract(&mut metadata.balance_y, amount)
    }

    /// Transfer `amount` from this contract to `recipient`
    fun transfer_x<X, Y>(amount: u64, recipient: address, metadata: &mut TokenPairMetadata<X, Y>) {
        let coins = extract_x(amount, metadata);
        Coin::deposit(recipient, coins);
    }

    /// Transfer `amount` from this contract to `recipient`
    fun transfer_y<X, Y>(amount: u64, recipient: address, metadata: &mut TokenPairMetadata<X, Y>) {
        let coins = extract_y(amount, metadata);
        Coin::deposit(recipient, coins);
    }

    fun mint_fee<X, Y>(reservex: u64, reservey: u64, metadata: &mut TokenPairMetadata<X, Y>) {
        if (metadata.fee_on) {
            if (metadata.k_last != 0) {
                let root_k = Math::sqrt(
                    SafeMath::mul(
                        (reservex as u128),
                        (reservey as u128)
                    )
                );
                let root_k_last = Math::sqrt(metadata.k_last);
                if (root_k > root_k_last) {
                    let total_supply = (total_lp_supply<X, Y>() as u128);

                    let numerator = SafeMath::mul(
                        total_supply,
                        SafeMath::sub(root_k, root_k_last)
                    );

                    let denominator = SafeMath::add(
                        root_k_last,
                        SafeMath::mul(root_k, 5u128)
                    );

                    let liquidity = (SafeMath::div(
                        numerator,
                        denominator
                    ) as u64);
                    mint_lp_to<X, Y>(metadata.fee_to, liquidity, &metadata.mint_cap);
                }
            }
        } else if (metadata.k_last != 0) metadata.k_last = 0;
    }

    // ================ Tests ================
    #[test_only]
    struct Token0 has key {}

    #[test_only]
    struct Token1 has key {}

    #[test_only]
    struct CapContainer<phantom T: key> has key {
        mc: Coin::MintCapability<T>,
        bc: Coin::BurnCapability<T>
    }

    #[test_only]
    fun expand_to_decimals(num: u64, decimals: u8): u64 {
        num * (Math::pow(10, decimals) as u64)
    }

    #[test_only]
    fun mint_lp_to_self<X, Y>(amount: u64) acquires TokenPairMetadata {
        let metadata = borrow_global_mut<TokenPairMetadata<X, Y>>(@HippoSwap);
        Coin::merge(
            &mut metadata.lp,
            Coin::mint(amount, &metadata.mint_cap)
        );
    }

    #[test_only]
    fun issue_token<T: key>(admin: &signer, to: &signer, name: vector<u8>, total_supply: u64) {
        let (mc, bc) = Coin::initialize<T>(
            admin,
            ASCII::string(name),
            ASCII::string(name),
            8u64,
            true
        );

        Coin::register_internal<T>(admin);
        Coin::register_internal<T>(to);

        let a = Coin::mint(total_supply, &mc);
        Coin::deposit(Signer::address_of(to), a);
        move_to<CapContainer<T>>(admin, CapContainer{ mc, bc });
    }

    #[test(admin = @HippoSwap)]
    public fun init_works(admin: signer) {
        let fee_to = Signer::address_of(&admin);
        create_token_pair<Token0, Token1>(
            &admin,
            fee_to,
            true,
            b"name",
            b"symbol"
        );
    }

    #[test(admin = @HippoSwap, token_owner = @0x02, lp_provider = @0x03, lock = @0x01, core = @0xa550c18)]
    public fun mint_works(admin: signer, token_owner: signer, lp_provider: signer, lock: signer, core: signer)
        acquires TokenPairReserve, TokenPairMetadata
    {
        // initial setup work
        let decimals: u8 = 8;
        let total_supply: u64 = (expand_to_decimals(1000000, 8) as u64);

        issue_token<Token0>(&admin, &token_owner, b"t0", total_supply);
        issue_token<Token1>(&admin, &token_owner, b"t1", total_supply);

        let fee_to = Signer::address_of(&admin);
        create_token_pair<Token0, Token1>(
            &admin,
            fee_to,
            true,
            b"name",
            b"symbol"
        );

        Timestamp::set_time_has_started_for_testing(&core);
        register_account<Token0, Token1>(&lp_provider);
        register_account<Token0, Token1>(&lock);

        Coin::register_internal<Token0>(&lp_provider);
        Coin::register_internal<Token1>(&lp_provider);

        // now perform the test
        let amount_x = expand_to_decimals(1u64, decimals);
        let amount_y = expand_to_decimals(4u64, decimals);
        Coin::deposit(Signer::address_of(&lp_provider), Coin::withdraw<Token0>(&token_owner, amount_x));
        Coin::deposit(Signer::address_of(&lp_provider), Coin::withdraw<Token1>(&token_owner, amount_y));
        add_liquidity<Token0, Token1>(&lp_provider, amount_x, amount_y);

        // now performing checks
        let expected_liquidity = expand_to_decimals(2u64, decimals);

        // check contract balance of Token0 and Token1
        let (b0, b1) = token_balances<Token0, Token1>();
        assert!(b0 == amount_x, 0);
        assert!(b1 == amount_y, 0);

        // check liquidities
        assert!(
            total_lp_supply<Token0, Token1>() == expected_liquidity,
            0
        );
        assert!(
            lp_balance<Token0, Token1>(Signer::address_of(&lp_provider)) == expected_liquidity - (MINIMUM_LIQUIDITY as u64),
            0
        );

        // check reserves
        let (r0, r1, _) = get_reserves<Token0, Token1>();
        assert!(r0 == amount_x, 0);
        assert!(r1 == amount_y, 0);
    }

    #[test(admin = @HippoSwap, token_owner = @0x02, lp_provider = @0x03, lock = @0x01, core = @0xa550c18)]
    public fun remove_liquidity_works(admin: signer, token_owner: signer, lp_provider: signer, lock: signer, core: signer)
        acquires TokenPairReserve, TokenPairMetadata
    {
        // initial setup work
        let decimals: u8 = 8;
        let total_supply: u64 = (expand_to_decimals(1000000, 8) as u64);

        issue_token<Token0>(&admin, &token_owner, b"t0", total_supply);
        issue_token<Token1>(&admin, &token_owner, b"t1", total_supply);

        let fee_to = Signer::address_of(&admin);
        create_token_pair<Token0, Token1>(
            &admin,
            fee_to,
            true,
            b"name",
            b"symbol"
        );

        Timestamp::set_time_has_started_for_testing(&core);
        register_account<Token0, Token1>(&lp_provider);
        register_account<Token0, Token1>(&lock);
        Coin::register_internal<Token0>(&lp_provider);
        Coin::register_internal<Token1>(&lp_provider);

        let amount_x = expand_to_decimals(3u64, decimals);
        let amount_y = expand_to_decimals(3u64, decimals);
        Coin::deposit(Signer::address_of(&lp_provider), Coin::withdraw<Token0>(&token_owner, amount_x));
        Coin::deposit(Signer::address_of(&lp_provider), Coin::withdraw<Token1>(&token_owner, amount_y));
        add_liquidity<Token0, Token1>(&lp_provider, amount_x, amount_y);

        let expected_liquidity = expand_to_decimals(3u64, decimals);

        // now perform the test
        remove_liquidity<Token0, Token1>(
            &lp_provider,
            expected_liquidity - (MINIMUM_LIQUIDITY as u64),
            expected_liquidity - (MINIMUM_LIQUIDITY as u64),
            expected_liquidity - (MINIMUM_LIQUIDITY as u64)
        );

        // now performing checks
        assert!(
            total_lp_supply<Token0, Token1>() == (MINIMUM_LIQUIDITY as u64),
            0
        );
        assert!(
            lp_balance<Token0, Token1>(Signer::address_of(&lp_provider)) == 0u64,
            0
        );
        let (b0, b1) = token_balances<Token0, Token1>();
        assert!(b0 == (MINIMUM_LIQUIDITY as u64), 0);
        assert!(b1 == (MINIMUM_LIQUIDITY as u64), 0);

        assert!(Coin::balance<Token0>(Signer::address_of(&lp_provider)) == amount_x - (MINIMUM_LIQUIDITY as u64), 0);
        assert!(Coin::balance<Token1>(Signer::address_of(&lp_provider)) == amount_y - (MINIMUM_LIQUIDITY as u64), 0);
    }

    #[test(admin = @HippoSwap, token_owner = @0x02, lp_provider = @0x03, lock = @0x01, core = @0xa550c18)]
    public fun swap_x_works(admin: signer, token_owner: signer, lp_provider: signer, lock: signer, core: signer)
        acquires TokenPairReserve, TokenPairMetadata
    {
        // initial setup work
        let decimals: u8 = 8;
        let total_supply: u64 = (expand_to_decimals(1000000, 8) as u64);

        issue_token<Token0>(&admin, &token_owner, b"t0", total_supply);
        issue_token<Token1>(&admin, &token_owner, b"t1", total_supply);

        let fee_to = Signer::address_of(&admin);
        create_token_pair<Token0, Token1>(
            &admin,
            fee_to,
            true,
            b"name",
            b"symbol"
        );

        Timestamp::set_time_has_started_for_testing(&core);
        register_account<Token0, Token1>(&lp_provider);
        register_account<Token0, Token1>(&lock);
        register_account<Token0, Token1>(&token_owner);
        Coin::register_internal<Token0>(&lp_provider);
        Coin::register_internal<Token1>(&lp_provider);

        let amount_x = expand_to_decimals(5u64, decimals);
        let amount_y = expand_to_decimals(10u64, decimals);
        add_liquidity<Token0, Token1>(&token_owner, amount_x, amount_y);

        let swap_amount = expand_to_decimals(1u64, decimals);
        let expected_output_amount = 160000001u64;
        deposit_x<Token0, Token1>(Coin::withdraw<Token0>(&token_owner, swap_amount));

        let (x, y) = swap<Token0, Token1>(0, expected_output_amount);
        Coin::deposit(Signer::address_of(&lp_provider), x);
        Coin::deposit(Signer::address_of(&lp_provider), y);

        let (reserve_x, reserve_y, _) = get_reserves<Token0, Token1>();
        assert!(reserve_x == amount_x + swap_amount, 0);
        assert!(reserve_y == amount_y - expected_output_amount, 0);

        let (b0, b1) = token_balances<Token0, Token1>();
        assert!(b0 == amount_x + swap_amount, 0);
        assert!(b1 == amount_y - expected_output_amount, 0);

        assert!(
            Coin::balance<Token0>(Signer::address_of(&lp_provider)) == 0,
            0
        );
        assert!(
            Coin::balance<Token1>(Signer::address_of(&lp_provider)) == expected_output_amount,
            0
        );
    }
}