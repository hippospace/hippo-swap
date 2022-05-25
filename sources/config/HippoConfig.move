module HippoSwap::HippoConfig {

    public fun admin_address(): address {
        @HippoSwap
    }

    public fun fee_address(): address {
        @HippoSwapFee
    }

    #[test(admin = @HippoSwap, core_resource_account = @CoreResources)]
    fun addresses() {
        admin_address();
        fee_address();
    }

}
