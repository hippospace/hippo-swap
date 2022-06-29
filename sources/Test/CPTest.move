#[test_only]
module HippoSwap::CPTest {

    use HippoSwap::MockCoin::{WUSDT, WBTC};
    use HippoSwap::TestShared;
    use HippoSwap::Router;
    use HippoSwap::CPScripts;

    // Keep the consts the same with TestShared.move.


    const ADMIN: address = @HippoSwap;
    const INVESTOR: address = @0x2FFF;
    const SWAPPER: address = @0x2FFE;

    const POOL_TYPE_CONSTANT_PRODUCT: u8 = 1;
    const POOL_TYPE_STABLE_CURVE: u8 = 2;
    const POOL_TYPE_PIECEWISE: u8 = 3;

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

    const LABEL_SAVE_POINT: u128 = 333000000000000000000000000000000000000;
    const LABEL_RESERVE_XY: u128 = 333000000000000000000000000000000000001;
    const LABEL_FEE: u128 = 333000000000000000000000000000000000002;
    const LABEL_LPTOKEN_SUPPLY: u128 = 333000000000000000000000000000000000003;

    const INC: u8 = 0;
    const DEC: u8 = 1;

    const ADD_LIQUIDITY: u8 = 0;
    const SWAP: u8 = 1;
    const REMOVE_LIQUIDITY: u8 = 2;

    // Keep the consts the same with TestShared.move.

    struct PoolDelta has drop {
        sx: u8,
        sy: u8,
        slp: u8,
        sfx: u8,
        sfy: u8,
        sflp: u8,
        // sign_reserve_x, ... sign_fee_x, sign_fee_y, sign_fee_lp
        dx: u64,
        dy: u64,
        dlp: u64,
        dfx: u64,
        dfy: u64,
        dflp: u64,
        // delta_reserve_x, ... delta_fee_lp,
    }

    struct WalletDelta has drop {
        sx: u8,
        sy: u8,
        slp: u8,
        // signs
        dx: u64,
        dy: u64,
        dlp: u64              // delta values
    }

    struct TransactionParams has drop {
        amt_x: u64,
        // amount x in value
        amt_y: u64,
        // amount y in value
        amt_lp: u64,
        // amount lp in value
        p: PoolDelta,
        // expected pool delta values
        w: WalletDelta,
        // expected wallet delta values
    }

    #[test_only]
    fun new_transaction_param(
        amt_x: u64, amt_y: u64, amt_lp: u64,
        sx: u8, sy: u8, slp: u8, sfx: u8, sfy: u8, sflp: u8,
        dx: u64, dy: u64, dlp: u64, dfx: u64, dfy: u64, dflp: u64,
        wsx: u8, wsy: u8, wslp: u8,
        wdx: u64, wdy: u64, wdlp: u64
    ): TransactionParams {
        TransactionParams{
            amt_x, amt_y, amt_lp,
            p: PoolDelta{
                sx, sy, slp, sfx, sfy, sflp,
                dx, dy, dlp, dfx, dfy, dflp
            },
            w: WalletDelta{
                sx: wsx, sy: wsy, slp: wslp,
                dx: wdx, dy: wdy, dlp: wdlp
            },
        }
    }

    #[test_only]
    fun add_param(
        amt_x: u64, amt_y: u64, dx: u64, dy: u64, dlp: u64, dflp: u64, dwlp: u64
    ): TransactionParams {
        TransactionParams{
            amt_x, amt_y, amt_lp: 0,
            p: PoolDelta{
                sx: INC, sy: INC, slp: INC, sfx: INC, sfy: INC, sflp: INC,
                dx, dy, dlp, dfx: 0, dfy: 0, dflp
            },
            w: WalletDelta{
                sx: DEC, sy: DEC, slp: INC,
                dx: amt_x, dy: amt_y, dlp: dwlp
            },
        }
    }

    #[test_only]
    fun swap_param(
        amt_x: u64, amt_y: u64, dx: u64, dy: u64, dfx: u64, dfy: u64, receive_amt: u64
    ): TransactionParams {
        let (sx, sy, wdx, wdy): (u8, u8, u64, u64);
        if (amt_x>0) {
            (sx, sy, wdx, wdy) = (INC, DEC, amt_x, receive_amt);
        } else {
            (sx, sy, wdx, wdy) = (DEC, INC, receive_amt, amt_y);
        };
        TransactionParams{
            amt_x, amt_y, amt_lp: 0,
            p: PoolDelta{
                sx, sy, slp: INC, sfx: INC, sfy: INC, sflp: INC,
                dx, dy, dlp: 0, dfx, dfy, dflp: 0
            },
            w: WalletDelta{
                sx: sy, sy: sx, slp: INC,
                dx: wdx, dy: wdy, dlp: 0
            },
        }
    }

    #[test_only]
    fun remove_param(
        amt_lp: u64, dx: u64, dy: u64, dlp: u64, dflp: u64
    ): TransactionParams {
        TransactionParams{
            amt_x: 0, amt_y: 0, amt_lp,
            p: PoolDelta{
                sx: DEC, sy: DEC, slp: DEC, sfx: DEC, sfy: DEC, sflp: INC,
                dx, dy, dlp, dfx: 0, dfy: 0, dflp
            },
            w: WalletDelta{
                sx: INC, sy: INC, slp: DEC,
                dx, dy, dlp: amt_lp
            },
        }
    }

    #[test_only]
    fun perform_transaction<X, Y>(trader: &signer, pool_type: u8, action: u8, print_debug: bool, param: TransactionParams) {
        if (action == ADD_LIQUIDITY) {
            Router::add_liquidity_route<X, Y>(trader, pool_type, param.amt_x, param.amt_y);
        } else if (action == SWAP) {
            CPScripts::swap<X, Y>(trader, param.amt_x, param.amt_y, 0, 0);
        } else if (action == REMOVE_LIQUIDITY) {
            Router::remove_liquidity_route<X, Y>(trader, pool_type, param.amt_lp, param.amt_x, param.amt_y);
        };
        if (print_debug) {
            TestShared::debug_print_comparision<X, Y>(pool_type);
            TestShared::debug_print_wallet_comparision<X, Y>(trader, pool_type);
        };
        TestShared::assert_pool_delta<X, Y>(pool_type, true,
            param.p.sx,
            param.p.sy,
            param.p.slp,
            param.p.sfx,
            param.p.sfy,
            param.p.sflp,
            param.p.dx,
            param.p.dy,
            param.p.dlp,
            param.p.dfx,
            param.p.dfy,
            param.p.dflp,
        );
        TestShared::assert_wallet_delta<X, Y>(trader, pool_type, true,
            param.w.sx, param.w.sy, param.w.slp,
            param.w.dx, param.w.dy, param.w.dlp
        );
    }

    #[test_only]
    public fun test_pool_case<X, Y>(
        admin: &signer, investor: &signer, swapper: &signer, core: &signer,
        print_debug: bool,
        skip_swap: bool,
        pool_type: u8,
        decimal_x: u64, // The decimal of coin x
        decimal_y: u64, // The decimal of coin y
        fee: u64,
        protocal_fee: u64,
        add_1: TransactionParams,
        add_2: TransactionParams,
        swap_1: TransactionParams,
        remove_1: TransactionParams
    ) {
        TestShared::prepare_for_test<X, Y>(admin, investor, swapper, core, pool_type, decimal_x, decimal_y,
            0, 0, 0, 0, 0, fee, protocal_fee
        );
        let liquidity_x = add_1.amt_x + add_2.amt_x;
        let liquidity_y = add_1.amt_y + add_2.amt_y;

        TestShared::fund_for_participants<X, Y>(investor, liquidity_x, liquidity_y);
        TestShared::sync_wallet_save_point<X, Y>(investor, pool_type);
        TestShared::fund_for_participants<X, Y>(swapper, swap_1.amt_x, swap_1.amt_y);
        TestShared::sync_wallet_save_point<X, Y>(swapper, pool_type);
        TestShared::assert_pool_delta<X, Y>(pool_type, false,
            INC, INC, INC, INC, INC, INC,
            0, 0, 0, 0, 0, 0
        );

        if (print_debug) {
            TestShared::debug_print_wallet_comparision<X, Y>(swapper, pool_type);
        };
        perform_transaction<X, Y>(investor, pool_type, ADD_LIQUIDITY, print_debug, add_1);
        perform_transaction<X, Y>(investor, pool_type, ADD_LIQUIDITY, print_debug, add_2);
        if (!skip_swap) {
            perform_transaction<X, Y>(swapper, pool_type, SWAP, print_debug, swap_1);
        };
        perform_transaction<X, Y>(investor, pool_type, REMOVE_LIQUIDITY, print_debug, remove_1);
    }

    #[test(admin = @HippoSwap, investor = @0x2FFF, swapper = @0x2FFE, core = @0xa550c18)]
    public fun test_pool_constant_product_1(admin: &signer, investor: &signer, swapper: &signer, core: &signer) {
        // tiny swap amount
        let (pool_type, print_debug) = (POOL_TYPE_CONSTANT_PRODUCT, true);
        let (decimal_x, decimal_y, fee, protocal_fee) = (8, 6, 100, 100000);
        let add_1 = add_param(P15, P13, P15, P13, P14, 1000, P14 - 1000);
        let add_2 = add_param(P15, P13, P15, P13, P14, 0, P14);
        let swap = swap_param(P8, 0, P8, P6 - 3001, 0, 0, P6 - 3001);
        let remove_1 = remove_param(2 * P10, 2*P11 + 9997, 2 * P9 - 100, 2*P10-2500, 2500);
        test_pool_case<WBTC, WUSDT>(admin, investor, swapper, core,
            print_debug, false, pool_type, decimal_x, decimal_y, fee, protocal_fee, add_1, add_2, swap, remove_1
        );
    }

}
