module HippoSwap::Utils {
    use Std::Vector;
    use AptosFramework::TypeInfo;

    const COMPARE_GREATER: u8 = 2;
    const COMPARE_EQUAL: u8 = 1;
    const COMPARE_LESS: u8 = 0;

    /// This function assumes the TypeInfo module and struct do not change over time!
    public fun is_tokens_sorted<T0, T1>(): bool {
        let t0 = TypeInfo::type_of<T0>();
        let n0 = TypeInfo::module_name(&t0);
        let s0 = TypeInfo::struct_name(&t0);

        let t1 = TypeInfo::type_of<T1>();
        let n1 = TypeInfo::module_name(&t1);
        let s1 = TypeInfo::struct_name(&t1);

        let name_compare = compare_vec(&n0, &n1);
        let r = if (name_compare != COMPARE_EQUAL) { name_compare }
        else { compare_vec(&s0, &s1) };

        r == COMPARE_LESS
    }

    /// This is custom vec comparison logic, only for `is_tokens_sorted`
    fun compare_vec(v1: &vector<u8>, v2: &vector<u8>): u8 {
        let (n1, n2) = (Vector::length(v1), Vector::length(v2));
        let r = compare_u64(n1, n2);
        if (r != COMPARE_EQUAL) { r }
        else {
            let i = 0u64;
            loop {
                // we have exhausted the vecs
                if (i == n1) { return COMPARE_EQUAL };
                let r = compare_u8(*Vector::borrow(v1, i), *Vector::borrow(v2, i));
                if (r != COMPARE_EQUAL) { return r };

                i = i + 1;
            }
        }
    }

    fun compare_u8(a: u8, b: u8): u8 {
        if (a > b) { COMPARE_GREATER }
        else if (a == b) { COMPARE_EQUAL }
        else { COMPARE_LESS }
    }

    fun compare_u64(a: u64, b: u64): u8 {
        if (a > b) { COMPARE_GREATER }
        else if (a == b) { COMPARE_EQUAL }
        else { COMPARE_LESS }
    }

    #[test_only]
    struct T0 {}
    #[test_only]
    struct T1 {}

    #[test]
    fun is_tokens_sorted_works() {
        assert!(
            is_tokens_sorted<T0, T1>(),
            0
        );

        assert!(
            !is_tokens_sorted<T0, T0>(),
            0
        );
    }

    #[test]
    fun compare_vector_works() {
        let v1 = Vector::empty<u8>();
        let v2 = Vector::empty<u8>();
        assert!(compare_vec(&v1, &v2) == COMPARE_EQUAL, 0);

        Vector::push_back(&mut v1, 5);
        Vector::push_back(&mut v2, 5);
        assert!(compare_vec(&v1, &v2) == COMPARE_EQUAL, 0);

        Vector::push_back(&mut v1, 6);
        Vector::push_back(&mut v2, 7);
        assert!(compare_vec(&v1, &v2) == COMPARE_LESS, 0);
        assert!(compare_vec(&v2, &v1) == COMPARE_GREATER, 0);

        Vector::push_back(&mut v1, 6);
        assert!(compare_vec(&v1, &v2) == COMPARE_GREATER, 0);
        assert!(compare_vec(&v2, &v1) == COMPARE_LESS, 0);
    }
}
