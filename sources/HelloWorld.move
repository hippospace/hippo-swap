module HippoSwap::HelloWorld {
    public fun hello_world(): bool {
        true
    }

    #[test]
    fun test_works() {
        assert!(hello_world(), 0);
    }
}