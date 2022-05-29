// token holder address, not admin address
address HippoSwap {
module MockCoin {
    use AptosFramework::Coin;
    use AptosFramework::TypeInfo;
    use Std::ASCII;
    use Std::Signer;

    spec module {
        pragma verify = false;
    }

    struct TokenSharedCapability<phantom TokenType> has key, store {
        mint: Coin::MintCapability<TokenType>,
        burn: Coin::BurnCapability<TokenType>,
    }

    // mock BTC token
    struct WBTC has copy, drop, store {}

    // mock ETH token
    struct WETH has copy, drop, store {}

    // mock USDT token
    struct WUSDT has copy, drop, store {}

    // mock USDC token
    struct WUSDC has copy, drop, store {}

    // mock DAI token
    struct WDAI has copy, drop, store {}

    // mock DOT token
    struct WDOT has copy, drop, store {}

    // mock SOL token
    struct WSOL has copy, drop, store {}


    public fun initialize<TokenType>(account: &signer, decimals: u64){
        let name = ASCII::string(TypeInfo::struct_name(&TypeInfo::type_of<TokenType>()));
        let (mint_capability, burn_capability) = Coin::initialize<TokenType>(
            account,
            name,
            name,
            decimals,
            true
        );
        Coin::register_internal<TokenType>(account);

        move_to(account, TokenSharedCapability { mint: mint_capability, burn: burn_capability });
    }

    public fun mint<TokenType>(amount: u64): Coin::Coin<TokenType> acquires TokenSharedCapability{
        //token holder address
        let addr = TypeInfo::account_address(&TypeInfo::type_of<TokenType>());
        let cap = borrow_global<TokenSharedCapability<TokenType>>(addr);
        Coin::mint<TokenType>( amount, &cap.mint,)
    }

    public fun burn<TokenType>(tokens: Coin::Coin<TokenType>) acquires TokenSharedCapability{
        //token holder address
        let addr = TypeInfo::account_address(&TypeInfo::type_of<TokenType>());
        let cap = borrow_global<TokenSharedCapability<TokenType>>(addr);
        Coin::burn<TokenType>(tokens, &cap.burn);
    }

    public fun faucet_mint_to<TokenType>(to: &signer, amount: u64) acquires TokenSharedCapability {
        let to_addr = Signer::address_of(to);
        if (!Coin::is_account_registered<TokenType>(to_addr)) {
            Coin::register_internal<TokenType>(to);
        };
        let coin = mint<TokenType>(amount);
        Coin::deposit(to_addr, coin);
    }

    public(script) fun faucet_mint_to_script<TokenType>(to: &signer, amount: u64) acquires  TokenSharedCapability {
        faucet_mint_to<TokenType>(to, amount);
    }

//    #[test(admin = @HippoSwap, core_resource_account = @CoreResources)]
//    fun mint_mock_coin(admin: &signer, core_resource_account: &signer)  acquires TokenSharedCapability {
//        use AptosFramework::Genesis;
//        Genesis::setup(core_resource_account);
//
//        initialize<WETH>(admin, 18);
//        let x = mint<WETH>(10);
//        burn(x)
//    }
}

}

