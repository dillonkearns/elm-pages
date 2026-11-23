it("HEAD request gets the same status and headers as GET, without a body", () => {
    cy.request("GET", "/test/response-headers").then((getResponse) => {
        cy.request({
            method: "HEAD",
            url: "/test/response-headers",
            failOnStatusCode: false,
        }).then((headResponse) => {
            expect(headResponse.status).to.eq(getResponse.status);
            expect(headResponse.headers).to.include({
                "x-powered-by": "my-framework",
            });
            expect(headResponse.body).to.be.empty;
        });
    });
});
