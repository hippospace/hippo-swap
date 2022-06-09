module HippoSwap::MockDeploy {
    use HippoSwap::MockCoin;
    use TokenRegistry::TokenRegistry;
    use AptosFramework::Coin;

    public fun init_coin_and_create_store<CoinType>(
        admin: &signer,
        name: vector<u8>,
        symbol: vector<u8>,
    ) {
        // create CoinInfo
        if (!Coin::is_coin_initialized<CoinType>()) {
            MockCoin::initialize<CoinType>(admin, 8);
        };

        // add coin to registry
        if (!TokenRegistry::has_token<CoinType>(@HippoSwap)) {
            TokenRegistry::add_token<CoinType>(
                admin,
                name,
                symbol,
                name,
                8,
                b"",
                b"",
            );
        }
    }

    #[test(admin = @HippoSwap, core = @CoreResources, vm = @0, trader = @0xFFFFFF01, )]
    fun test_init_coin(admin: &signer) {
        use HippoSwap::MockCoin;
        TokenRegistry::initialize(admin);
        init_coin_and_create_store<MockCoin::WBTC>(admin, b"Bitcoin", b"BTC");
    }
}
