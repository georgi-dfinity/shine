import OrderedMap "mo:base/OrderedMap";
import Nat "mo:base/Nat";
import Text "mo:base/Text";
import Iter "mo:base/Iter";
import Principal "mo:base/Principal";
import Debug "mo:base/Debug";
import Buffer "mo:base/Buffer";
import Blob "mo:base/Blob";
import Error "mo:base/Error";
import Array "mo:base/Array";
import Result "mo:base/Result";
import Time "mo:base/Time";
import Int "mo:base/Int";
import Char "mo:base/Char";

actor {
    type Product = {
        id : Nat;
        name : Text;
        description : Text;
        price : Nat;
        category : Text;
        image : ?Text;
    };

    type Category = {
        name : Text;
        description : Text;
        image : ?Text;
    };

    type Status = {
        #checking : { userPrincipal : ?Text };
        #failed : { error : Text; userPrincipal : ?Text };
        #completed : { response : Text; userPrincipal : ?Text };
    };

    type CheckoutLineItem = {
        product_id : Nat;
        quantity : Nat;
    };

    type PaginationResult<T> = {
        items : [T];
        totalItems : Nat;
        totalPages : Nat;
        currentPage : Nat;
        hasNextPage : Bool;
        hasPrevPage : Bool;
    };

    transient let natMap = OrderedMap.Make<Nat>(Nat.compare);
    transient let textMap = OrderedMap.Make<Text>(Text.compare);
    transient let principalMap = OrderedMap.Make<Principal>(Principal.compare);

    var authorization = "";
    var nonce = 0;
    var nextProductId : Nat = 1;
    var products : OrderedMap.Map<Nat, Product> = natMap.empty<Product>();
    var categories : OrderedMap.Map<Text, Category> = textMap.empty<Category>();
    var transactions : OrderedMap.Map<Text, Status> = textMap.empty<Status>();

    private let MAX_TRANSACTIONS_PER_USER : Nat = 1000;
    var userProfiles : OrderedMap.Map<Principal, Text> = principalMap.empty();
    var adminPrincipals : [Principal] = [];
    var isInitialized : Bool = false;
    var allowedOrigins : [Text] = [];

    let ic = actor ("aaaaa-aa") : actor {
        http_request : ({
            url : Text;
            max_response_bytes : ?Nat;
            headers : [{ name : Text; value : Text }];
            body : ?Blob;
            method : { #get; #post };
            transform : ?{
                function : shared query ({
                    response : {
                        status : Nat;
                        headers : [{ name : Text; value : Text }];
                        body : Blob;
                    };
                }) -> async {
                    status : Nat;
                    headers : [{ name : Text; value : Text }];
                    body : Blob;
                };
                context : Blob;
            };
        }) -> async {
            status : Nat;
            headers : [{ name : Text; value : Text }];
            body : Blob;
        };
    };

    private func requireAdmin(caller : Principal) {
        if (not hasAdminPermission(caller)) {
            Debug.trap("Unauthorized: Admin access required");
        };
    };

    private func hasAdminPermission(caller : Principal) : Bool {
        Array.find<Principal>(adminPrincipals, func(admin) { admin == caller }) != null;
    };

    private func paginateArray<T>(items : [T], page : Nat, limit : Nat) : PaginationResult<T> {
        let totalItems = items.size();
        let safeLimit = if (limit == 0) 1 else limit;
        let totalPages = if (totalItems == 0 or safeLimit == 0) 1 else (totalItems + safeLimit - 1) / safeLimit;
        let currentPage = Nat.min(Nat.max(page, 1), totalPages);
        let startIndex = if (currentPage > 0) (currentPage - 1) * safeLimit else 0;
        let endIndex = Nat.min(startIndex + safeLimit, totalItems);
        let sliceLength = if (endIndex > startIndex) endIndex - startIndex else 0;

        {
            items = if (startIndex >= totalItems)[] else Array.subArray(items, startIndex, sliceLength);
            totalItems = totalItems;
            totalPages = totalPages;
            currentPage = currentPage;
            hasNextPage = currentPage < totalPages;
            hasPrevPage = currentPage > 1;
        };
    };

    private func validatePagination(page : ?Nat, limit : ?Nat) : (Nat, Nat) {
        let validatedPage = switch (page) {
            case (?p) {
                if (p == 0) Debug.trap("Page must be greater than 0");
                if (p > 10000) Debug.trap("Page number too large (max 10000)");
                p;
            };
            case null 1;
        };
        let validatedLimit = switch (limit) {
            case (?l) {
                if (l == 0) Debug.trap("Limit must be greater than 0");
                if (l > 100) Debug.trap("Limit too large (max 100)");
                l;
            };
            case null 10;
        };
        (validatedPage, validatedLimit);
    };

    public shared ({ caller }) func initializeData(
        initCategories : [Category],
        initProducts : [Product],
        initAllowedOrigins : [Text],
    ) : async Text {
        if (isInitialized) {
            return "Store already initialized. Only admins can reinitialize.";
        };

        var categoriesLoaded = 0;
        var productsLoaded = 0;

        // Load categories from input
        for (category in initCategories.vals()) {
            categories := textMap.put(categories, category.name, category);
            categoriesLoaded += 1;
        };

        // Load products from input
        for (product in initProducts.vals()) {
            products := natMap.put(products, product.id, product);
            if (product.id >= nextProductId) {
                nextProductId := product.id + 1;
            };
            productsLoaded += 1;
        };

        allowedOrigins := Array.map<Text, Text>(initAllowedOrigins, normalizeOrigin);
        isInitialized := true;
        "Initialized store with " # Nat.toText(categoriesLoaded) # " categories and " # Nat.toText(productsLoaded) # " products";
    };

    public shared ({ caller }) func initializeAuth() : async () {
        if (Principal.isAnonymous(caller)) Debug.trap("Anonymous principals cannot be admin");
        if (adminPrincipals.size() == 0) adminPrincipals := [caller];
    };

    public query ({ caller }) func isAdmin() : async Bool {
        hasAdminPermission(caller);
    };

    public shared ({ caller }) func addAdmin(newAdmin : Principal) : async () {
        requireAdmin(caller);
        if (Principal.isAnonymous(newAdmin)) {
            Debug.trap("Cannot add anonymous principal as admin");
        };
        if (Array.find<Principal>(adminPrincipals, func(admin) { admin == newAdmin }) != null) {
            Debug.trap("Principal is already an admin");
        };
        adminPrincipals := Array.append(adminPrincipals, [newAdmin]);
    };

    public shared ({ caller }) func removeAdmin(adminToRemove : Principal) : async () {
        requireAdmin(caller);
        if (adminPrincipals.size() <= 1) Debug.trap("Cannot remove the last admin");
        if (caller == adminToRemove) Debug.trap("Admins cannot remove themselves");
        adminPrincipals := Array.filter<Principal>(adminPrincipals, func(admin) { admin != adminToRemove });
    };

    public query ({ caller }) func getAdmins() : async [Principal] {
        requireAdmin(caller);
        adminPrincipals;
    };

    public shared ({ caller }) func setAuthorization(newAuthorization : Text) : async () {
        requireAdmin(caller);
        if (Text.size(newAuthorization) == 0) {
            Debug.trap("Authorization cannot be empty");
        };
        authorization := newAuthorization;
    };

    public shared ({ caller }) func addProduct(name : Text, description : Text, price : Nat, category : Text, image : ?Text) : async () {
        requireAdmin(caller);
        if (Text.size(name) == 0) {
            Debug.trap("Product name cannot be empty");
        };
        if (Text.size(name) > 255) {
            Debug.trap("Product name too long (max 255 characters)");
        };
        if (Text.size(description) == 0) {
            Debug.trap("Product description cannot be empty");
        };
        if (Text.size(description) > 1000) {
            Debug.trap("Product description too long (max 1000 characters)");
        };
        if (price == 0) {
            Debug.trap("Product price must be greater than 0");
        };
        if (Text.size(category) == 0) {
            Debug.trap("Product category cannot be empty");
        };
        if (textMap.get(categories, category) == null) {
            Debug.trap("Category does not exist");
        };
        let product : Product = {
            id = nextProductId;
            name = name;
            description = description;
            price = price;
            category = category;
            image = image;
        };
        products := natMap.put(products, nextProductId, product);
        nextProductId += 1;
    };

    public shared ({ caller }) func editProduct(id : Nat, name : Text, description : Text, price : Nat, category : Text, image : ?Text) : async () {
        requireAdmin(caller);
        if (Text.size(name) == 0) {
            Debug.trap("Product name cannot be empty");
        };
        if (Text.size(name) > 255) {
            Debug.trap("Product name too long (max 255 characters)");
        };
        if (Text.size(description) == 0) {
            Debug.trap("Product description cannot be empty");
        };
        if (Text.size(description) > 1000) {
            Debug.trap("Product description too long (max 1000 characters)");
        };
        if (price == 0) {
            Debug.trap("Product price must be greater than 0");
        };
        if (Text.size(category) == 0) {
            Debug.trap("Product category cannot be empty");
        };
        if (textMap.get(categories, category) == null) {
            Debug.trap("Category does not exist");
        };
        switch (natMap.get(products, id)) {
            case (?existingProduct) {
                let updatedProduct : Product = {
                    id = id;
                    name = name;
                    description = description;
                    price = price;
                    category = category;
                    image = image;
                };
                products := natMap.put(products, id, updatedProduct);
            };
            case null {
                Debug.trap("Product not found");
            };
        };
    };

    public shared ({ caller }) func deleteProduct(id : Nat) : async () {
        requireAdmin(caller);
        products := natMap.delete(products, id);
    };

    public shared ({ caller }) func addCategory(name : Text, description : Text, image : ?Text) : async () {
        requireAdmin(caller);
        if (Text.size(name) == 0) {
            Debug.trap("Category name cannot be empty");
        };
        if (Text.size(name) > 255) {
            Debug.trap("Category name too long (max 255 characters)");
        };
        if (Text.size(description) == 0) {
            Debug.trap("Category description cannot be empty");
        };
        if (Text.size(description) > 1000) {
            Debug.trap("Category description too long (max 1000 characters)");
        };
        if (textMap.get(categories, name) != null) {
            Debug.trap("Category already exists");
        };
        categories := textMap.put(categories, name, { name = name; description = description; image = image });
    };

    public shared ({ caller }) func deleteCategory(name : Text) : async () {
        requireAdmin(caller);
        if (Text.size(name) == 0) {
            Debug.trap("Category name cannot be empty");
        };
        if (textMap.get(categories, name) == null) {
            Debug.trap("Category not found");
        };
        let productsUsingCategory = Array.filter<Product>(
            Iter.toArray(natMap.vals(products)),
            func(product) { product.category == name },
        );
        if (productsUsingCategory.size() > 0) {
            Debug.trap("Cannot delete category: " # Nat.toText(productsUsingCategory.size()) # " product(s) still use this category");
        };
        categories := textMap.delete(categories, name);
    };

    public shared ({ caller }) func clearAllProducts() : async Text {
        requireAdmin(caller);
        let count = natMap.size(products);
        products := natMap.empty<Product>();
        nextProductId := 1;
        "Deleted " # Nat.toText(count) # " products";
    };

    public shared ({ caller }) func clearAllCategories() : async Text {
        requireAdmin(caller);
        let count = textMap.size(categories);
        categories := textMap.empty<Category>();
        "Deleted " # Nat.toText(count) # " categories";
    };

    public shared ({ caller }) func deleteTransaction(session_id : Text) : async Bool {
        requireAdmin(caller);
        switch (textMap.get(transactions, session_id)) {
            case (?_) {
                transactions := textMap.delete(transactions, session_id);
                true;
            };
            case null false;
        };
    };

    public shared ({ caller }) func clearAllTransactions() : async Text {
        requireAdmin(caller);
        let count = textMap.size(transactions);
        transactions := textMap.empty<Status>();
        "Deleted " # Nat.toText(count) # " transactions";
    };

    public query func getProducts(page : ?Nat, limit : ?Nat) : async PaginationResult<Product> {
        let (validatedPage, validatedLimit) = validatePagination(page, limit);
        paginateArray<Product>(Iter.toArray(natMap.vals(products)), validatedPage, validatedLimit);
    };

    public query func getProductsByCategory(category : Text, page : ?Nat, limit : ?Nat) : async PaginationResult<Product> {
        if (Text.size(category) == 0) {
            Debug.trap("Category cannot be empty");
        };

        let (validatedPage, validatedLimit) = validatePagination(page, limit);
        let filtered = Array.filter<Product>(Iter.toArray(natMap.vals(products)), func(p) { p.category == category });
        paginateArray<Product>(filtered, validatedPage, validatedLimit);
    };

    public query func getAllCategories() : async [Text] {
        Array.map<Category, Text>(Iter.toArray(textMap.vals(categories)), func(c) { c.name });
    };

    public query func getCategories(page : ?Nat, limit : ?Nat) : async PaginationResult<Category> {
        let (validatedPage, validatedLimit) = validatePagination(page, limit);
        paginateArray<Category>(Iter.toArray(textMap.vals(categories)), validatedPage, validatedLimit);
    };

    // HTTP Transform
    public query func transform({
        response : {
            status : Nat;
            headers : [{ name : Text; value : Text }];
            body : Blob;
        };
    }) : async {
        status : Nat;
        headers : [{ name : Text; value : Text }];
        body : Blob;
    } {
        { response with headers = [] };
    };

    private func getCurrentDay() : Int {
        let now = Time.now();
        let tenMinutesNanos = 1 * 60 * 1_000_000_000; // 1min in nanoseconds
        now / tenMinutesNanos * tenMinutesNanos;
    };

    private func generateNonce() : Nat {
        let currentNonce = nonce;
        nonce += 1;
        currentNonce;
    };

    private func callStripeWithKey(endpoint : Text, method : { #get; #post }, body : ?Text, idempotencyKey : Text) : async Text {
        let headers = Buffer.Buffer<{ name : Text; value : Text }>(5);

        headers.add({
            name = "content-type";
            value = if (method == #get) "application/json" else "application/x-www-form-urlencoded";
        });
        headers.add({
            name = "authorization";
            value = "Bearer " # authorization;
        });
        headers.add({
            name = "idempotency-key";
            value = idempotencyKey;
        });

        let http_request = {
            url = "https://api.stripe.com/" # endpoint;
            headers = Buffer.toArray(headers);
            max_response_bytes = ?8192;
            body = switch (body) {
                case (?b) ?Text.encodeUtf8(b);
                case null null;
            };
            method = method;
            transform = ?{ function = transform; context = Blob.fromArray([]) };
        };

        let response = await (with cycles = 230_850_258_000) ic.http_request(http_request);
        switch (Text.decodeUtf8(response.body)) {
            case (?text) text;
            case null "No value returned";
        };
    };

    private func callStripe(endpoint : Text, method : { #get; #post }, body : ?Text) : async Text {
        let uniqueNonce = generateNonce();
        let idempotencyKey = "key-" # Int.toText(getCurrentDay()) # Nat.toText(uniqueNonce);
        await callStripeWithKey(endpoint, method, body, idempotencyKey);
    };

    private func buildCheckoutSessionBody(lineItems : [CheckoutLineItem], successUrl : Text, cancelUrl : Text, clientReferenceId : ?Text) : Text {
        let params = Buffer.Buffer<Text>(10);
        var index = 0;

        for (item in lineItems.vals()) {
            switch (natMap.get(products, item.product_id)) {
                case (?product) {
                    let i = Nat.toText(index);
                    params.add("line_items[" # i # "][price_data][currency]=usd");
                    params.add("line_items[" # i # "][price_data][product_data][name]=" # urlEncode(product.name));
                    params.add("line_items[" # i # "][price_data][product_data][description]=" # urlEncode(product.description));
                    params.add("line_items[" # i # "][price_data][unit_amount]=" # Nat.toText(product.price));
                    params.add("line_items[" # i # "][quantity]=" # Nat.toText(item.quantity));
                    index += 1;
                };
                case null {};
            };
        };

        params.add("mode=payment");
        params.add("success_url=" # urlEncode(successUrl));
        params.add("cancel_url=" # urlEncode(cancelUrl));
        params.add("shipping_address_collection[allowed_countries][0]=US");
        params.add("shipping_address_collection[allowed_countries][1]=CA");
        switch (clientReferenceId) {
            case (?id) params.add("client_reference_id=" # urlEncode(id));
            case null {};
        };

        Text.join("&", params.vals());
    };

    private func extractJsonStringField(jsonText : Text, fieldName : Text) : ?Text {
        let patterns = ["\"" # fieldName # "\":\"", "\"" # fieldName # "\": \""];

        for (pattern in patterns.vals()) {
            if (Text.contains(jsonText, #text pattern)) {
                let parts = Text.split(jsonText, #text pattern);
                switch (parts.next()) {
                    case null {};
                    case (?_) {
                        switch (parts.next()) {
                            case (?afterPattern) {
                                switch (Text.split(afterPattern, #text "\"").next()) {
                                    case (?value) if (Text.size(value) > 0) return ?value;
                                    case _ {};
                                };
                            };
                            case null {};
                        };
                    };
                };
            };
        };

        if (Text.contains(jsonText, #text "\"client_reference_id\":null")) return null;
        null;
    };

    private func isPaymentSuccessful(paymentStatus : ?Text, sessionStatus : ?Text) : Bool {
        switch (paymentStatus, sessionStatus) {
            case (?"paid", ?"complete") true; // Standard successful payment
            case (?"no_payment_required", ?"complete") true; // Free checkout
            case (_, _) false; // All other cases
        };
    };

    private func enforceTransactionLimit() {
        if (textMap.size(transactions) >= MAX_TRANSACTIONS_PER_USER) {
            switch (textMap.entries(transactions).next()) {
                case (?(oldestKey, _)) {
                    transactions := textMap.delete(transactions, oldestKey);
                };
                case null {};
            };
        };
    };

    public shared ({ caller }) func addTransaction(session_id : Text) : async ?Status {
        if (Principal.isAnonymous(caller)) Debug.trap("Unauthorized: Anonymous users cannot add a transaction");
        if (Text.size(session_id) == 0) {
            Debug.trap("Session ID cannot be empty");
        };
        if (not Text.startsWith(session_id, #text "cs_")) {
            Debug.trap("Invalid session ID format");
        };
        let userPrincipal = ?Principal.toText(caller);
        try {
            if (textMap.get(transactions, session_id) == null) {
                transactions := textMap.put(transactions, session_id, #checking({ userPrincipal = userPrincipal }));
                let reply = await callStripe("v1/checkout/sessions/" # session_id, #get, null);

                if (Text.contains(reply, #text "\"error\"")) {
                    transactions := textMap.put(transactions, session_id, #failed({ error = "Stripe API error"; userPrincipal = userPrincipal }));
                } else {
                    let paymentStatus = extractJsonStringField(reply, "payment_status");
                    let sessionStatus = extractJsonStringField(reply, "status");

                    if (isPaymentSuccessful(paymentStatus, sessionStatus)) {
                        let clientReferenceId = extractJsonStringField(reply, "client_reference_id");
                        let extractedPrincipal = switch (clientReferenceId) {
                            case (?p) ?p;
                            case null userPrincipal;
                        };
                        transactions := textMap.put(transactions, session_id, #completed({ response = reply; userPrincipal = extractedPrincipal }));
                    } else {
                        let errorMsg = switch (paymentStatus, sessionStatus) {
                            case (?"unpaid", _) "Payment was not completed";
                            case (_, ?"expired") "Checkout session expired";
                            case (_, ?"open") "Checkout session still pending";
                            case (null, _) "Could not determine payment status";
                            case (_, null) "Could not determine session status";
                            case (?ps, ?ss) "Payment not successful. Payment status: " # ps # ", Session status: " # ss;
                        };

                        transactions := textMap.put(transactions, session_id, #failed({ error = errorMsg; userPrincipal = userPrincipal }));
                    };
                };
            };
        } catch (err) {
            transactions := textMap.put(transactions, session_id, #failed({ error = Error.message(err); userPrincipal = userPrincipal }));
        };

        textMap.get(transactions, session_id);
    };

    public query ({ caller }) func getTransactions() : async [(Text, Status)] {
        requireAdmin(caller);
        Iter.toArray(textMap.entries(transactions));
    };

    public query ({ caller }) func getTransactionsByPrincipal() : async [(Text, Status)] {
        if (Principal.isAnonymous(caller)) return [];

        let userPrincipal = Principal.toText(caller);
        Array.filter<(Text, Status)>(
            Iter.toArray(textMap.entries(transactions)),
            func((_, status)) {
                switch (status) {
                    case (#completed({ userPrincipal = ?p }) or #checking({ userPrincipal = ?p }) or #failed({ userPrincipal = ?p })) {
                        p == userPrincipal;
                    };
                    case _ false;
                };
            },
        );
    };

    public query ({ caller }) func getTransaction(session_id : Text) : async ?Status {
        if (Principal.isAnonymous(caller)) Debug.trap("Unauthorized: Anonymous users cannot access transactions");
        if (Text.size(session_id) == 0) {
            Debug.trap("Session ID cannot be empty");
        };

        switch (textMap.get(transactions, session_id)) {
            case (?status) {
                // Admin can access any transaction
                if (hasAdminPermission(caller)) {
                    return ?status;
                };

                // Non-admin users can only access their own transactions
                let userPrincipal = Principal.toText(caller);
                switch (status) {
                    case (#completed({ userPrincipal = ?p }) or #checking({ userPrincipal = ?p }) or #failed({ userPrincipal = ?p })) {
                        if (p == userPrincipal) {
                            return ?status;
                        };
                    };
                    case _ {};
                };
                Debug.trap("Unauthorized: You can only access your own transactions");
            };
            case null {
                null;
            };
        };
    };

    public shared ({ caller }) func getTransactionLineItems(session_id : Text, starting_after : ?Text) : async Text {
        if (Principal.isAnonymous(caller)) Debug.trap("Unauthorized: Anonymous users cannot access line items");
        if (Text.size(session_id) == 0) {
            Debug.trap("Session ID cannot be empty");
        };
        if (not Text.startsWith(session_id, #text "cs_")) {
            Debug.trap("Invalid session ID format");
        };
        var endpoint = "v1/checkout/sessions/" # session_id # "/line_items";
        switch (starting_after) {
            case (?id) if (Text.size(id) > 0) endpoint #= "?starting_after=" # id;
            case _ {};
        };
        try {
            await callStripe(endpoint, #get, null);
        } catch (err) {
            Debug.trap("Failed to get line items: " # Error.message(err));
        };
    };

    private func callStripeWithRetry(endpoint : Text, method : { #get; #post }, body : ?Text, maxRetries : Nat) : async Text {
        let uniqueNonce = generateNonce();
        let idempotencyKey = "key-" # Int.toText(getCurrentDay()) # Nat.toText(uniqueNonce);
        var attempt = 0;
        while (attempt <= maxRetries) {
            try {
                let result = await callStripeWithKey(endpoint, method, body, idempotencyKey);
                return result;
            } catch (err) {
                let errorMsg = Error.message(err);
                if (Text.contains(errorMsg, #text "409") and attempt < maxRetries) {
                    attempt += 1;
                } else {
                    throw err;
                };
            };
        };
        Debug.trap("Unexpected error in retry logic");
    };

    private func extractSessionId(response : Text) : ?Text {
        switch (extractJsonStringField(response, "id")) {
            case (?id) {
                if (Text.startsWith(id, #text "cs_")) {
                    ?id;
                } else {
                    null;
                };
            };
            case null null;
        };
    };

    private func validateCheckoutSession(
        sessionId : Text,
        expectedLineItems : [CheckoutLineItem],
        expectedSuccessUrl : Text,
        expectedCancelUrl : Text,
        expectedClientReferenceId : Text,
    ) : async Result.Result<(), Text> {
        let sessionData = try {
            await callStripe("v1/checkout/sessions/" # sessionId, #get, null);
        } catch (err) {
            return #err("Failed to retrieve session for validation: " # Error.message(err));
        };
        let cleanSessionData = Text.replace(sessionData, #text " ", "");
        if (not Text.contains(cleanSessionData, #text "\"mode\":\"payment\"")) {
            return #err("Session mode is not 'payment'");
        };
        let clientRefPattern = "\"client_reference_id\":\"" # expectedClientReferenceId # "\"";
        if (not Text.contains(cleanSessionData, #text clientRefPattern)) {
            return #err("Client reference ID does not match");
        };
        switch (extractJsonStringField(cleanSessionData, "success_url")) {
            case (?actualSuccessUrl) {
                if (normalizeOrigin(actualSuccessUrl) != normalizeOrigin(expectedSuccessUrl)) {
                    return #err("Success URL does not match expected");
                };
            };
            case null {
                return #err("Success URL not found in session");
            };
        };
        switch (extractJsonStringField(cleanSessionData, "cancel_url")) {
            case (?actualCancelUrl) {
                if (normalizeOrigin(actualCancelUrl) != normalizeOrigin(expectedCancelUrl)) {
                    return #err("Cancel URL does not match expected");
                };
            };
            case null {
                return #err("Cancel URL not found in session");
            };
        };
        #ok();
    };

    public shared ({ caller }) func createCheckoutSession(lineItems : [CheckoutLineItem], successUrl : Text, cancelUrl : Text) : async Text {
        if (Principal.isAnonymous(caller)) {
            Debug.trap("Anonymous users cannot create checkout sessions");
        };
        if (lineItems.size() == 0) {
            Debug.trap("Line items cannot be empty");
        };
        if (lineItems.size() > 100) {
            Debug.trap("Too many line items (max 100)");
        };
        if (not isValidCheckoutDomain(successUrl)) {
            Debug.trap("Success URL domain not allowed");
        };
        if (not isValidCheckoutDomain(cancelUrl)) {
            Debug.trap("Cancel URL domain not allowed");
        };
        for (item in lineItems.vals()) {
            if (item.quantity == 0) {
                Debug.trap("Line item quantity must be greater than 0");
            };
            if (item.quantity > 1000) {
                Debug.trap("Line item quantity too large (max 1000)");
            };
            switch (natMap.get(products, item.product_id)) {
                case null {
                    Debug.trap("Product with ID " # Nat.toText(item.product_id) # " not found");
                };
                case (?_) {};
            };
        };
        if (Text.size(successUrl) == 0) {
            Debug.trap("Success URL cannot be empty");
        };
        if (Text.size(successUrl) > 2000) {
            Debug.trap("Success URL too long (max 2000 characters)");
        };
        if (Text.size(cancelUrl) == 0) {
            Debug.trap("Cancel URL cannot be empty");
        };
        if (Text.size(cancelUrl) > 2000) {
            Debug.trap("Cancel URL too long (max 2000 characters)");
        };

        let clientReferenceId = Principal.toText(caller);
        let requestBody = buildCheckoutSessionBody(lineItems, successUrl, cancelUrl, ?clientReferenceId);
        let sessionResponse = try {
            await callStripeWithRetry("v1/checkout/sessions", #post, ?requestBody, 2);
        } catch (err) {
            Debug.trap("Failed to create checkout session: " # Error.message(err));
        };
        let sessionId = switch (extractSessionId(sessionResponse)) {
            case (?id) id;
            case null Debug.trap("Failed to extract session ID from response" # sessionResponse);
        };
        let validationResult = await validateCheckoutSession(sessionId, lineItems, successUrl, cancelUrl, clientReferenceId);
        switch (validationResult) {
            case (#ok()) sessionResponse;
            case (#err(msg)) Debug.trap("Session validation failed: " # msg);
        };
    };

    public query ({ caller }) func getUser() : async ?Text {
        principalMap.get(userProfiles, caller);
    };

    public shared ({ caller }) func setUser(name : Text) : async () {
        if (Principal.isAnonymous(caller)) {
            Debug.trap("Anonymous users cannot set user profiles");
        };
        if (Text.size(name) == 0) {
            Debug.trap("User name cannot be empty");
        };
        if (Text.size(name) > 255) {
            Debug.trap("User name too long (max 255 characters)");
        };
        let allowedChars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 -_";
        for (char in name.chars()) {
            if (not Text.contains(allowedChars, #char char)) {
                Debug.trap("User name contains invalid characters (only letters, numbers, spaces, hyphens, and underscores allowed)");
            };
        };
        userProfiles := principalMap.put(userProfiles, caller, name);
    };

    private func extractOrigin(url : Text) : Text {
        Text.replace(
            Text.replace(url, #text "https://", ""),
            #text "http://",
            "",
        );
    };

    private func normalizeOrigin(url : Text) : Text {
        Text.trimEnd(extractOrigin(url), #text "/");
    };

    private func isValidCheckoutDomain(url : Text) : Bool {
        let domain = normalizeOrigin(url);

        Array.find<Text>(
            allowedOrigins,
            func(allowed) { Text.startsWith(domain, #text allowed) },
        ) != null;
    };

    public shared ({ caller }) func addAllowedOrigin(newOrigin : Text) : async Text {
        requireAdmin(caller);
        let cleanOrigin = normalizeOrigin(newOrigin);
        if (cleanOrigin.size() == 0) {
            return "Invalid origin format";
        };
        if (Array.find<Text>(allowedOrigins, func(origin) { origin == cleanOrigin }) != null) {
            return "Origin already exists";
        };
        if (allowedOrigins.size() >= 10) {
            return "Maximum of 10 allowed origins reached";
        };
        allowedOrigins := Array.append(allowedOrigins, [cleanOrigin]);
        "Successfully added origin: " # cleanOrigin;
    };

    public shared ({ caller }) func removeAllowedOrigin(originToRemove : Text) : async Text {
        requireAdmin(caller);
        allowedOrigins := Array.filter<Text>(allowedOrigins, func(origin) { origin != originToRemove });
        "Successfully removed " # originToRemove # " from allowed origins";
    };

    public query ({ caller }) func getAllowedOrigins() : async [Text] {
        requireAdmin(caller);
        allowedOrigins;
    };

    private func urlEncode(text : Text) : Text {
        var encoded = "";
        for (char in text.chars()) {
            switch (char) {
                case (' ') encoded #= "%20";
                case ('!') encoded #= "%21";
                case ('\"') encoded #= "%22";
                case ('#') encoded #= "%23";
                case ('$') encoded #= "%24";
                case ('%') encoded #= "%25";
                case ('&') encoded #= "%26";
                case ('\'') encoded #= "%27";
                case ('(') encoded #= "%28";
                case (')') encoded #= "%29";
                case ('+') encoded #= "%2B";
                case (',') encoded #= "%2C";
                case ('/') encoded #= "%2F";
                case (':') encoded #= "%3A";
                case (';') encoded #= "%3B";
                case ('<') encoded #= "%3C";
                case ('=') encoded #= "%3D";
                case ('>') encoded #= "%3E";
                case ('?') encoded #= "%3F";
                case ('@') encoded #= "%40";
                case ('[') encoded #= "%5B";
                case ('\\') encoded #= "%5C";
                case (']') encoded #= "%5D";
                case ('^') encoded #= "%5E";
                case ('`') encoded #= "%60";
                case ('{') encoded #= "%7B";
                case ('|') encoded #= "%7C";
                case ('}') encoded #= "%7D";
                case (_) encoded #= Char.toText(char);
            };
        };
        encoded;
    };
};
