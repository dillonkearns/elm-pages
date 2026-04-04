it("proxy should reject elm-pages-internal:// URLs (env var)", () => {
    cy.request({
        method: "POST",
        url: "/api/proxy",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
            url: "elm-pages-internal://env",
            body: "SUPER_SECRET_VALUE",
        }),
        failOnStatusCode: false,
    }).then((res) => {
        cy.log(`Status: ${res.status}`);
        cy.log(
            `Body: ${typeof res.body === "string" ? res.body : JSON.stringify(res.body)}`
        );

        const body =
            typeof res.body === "string" ? res.body : JSON.stringify(res.body);

        expect(body).to.not.include("my-secret-123");
    });
});

it("proxy should reject elm-pages-internal:// URLs (timestamp)", () => {
    cy.request({
        method: "POST",
        url: "/api/proxy",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ url: "elm-pages-internal://now" }),
        failOnStatusCode: false,
    }).then((res) => {
        cy.log(`Status: ${res.status}`);
        cy.log(
            `Body: ${typeof res.body === "string" ? res.body : JSON.stringify(res.body)}`
        );

        const body =
            typeof res.body === "string" ? res.body : JSON.stringify(res.body);

        expect(body).to.not.match(/\d{13,}/);
    });
});

export {};
