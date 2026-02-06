it("JSON body", () => {
    const body = { first: "Dillon" };
    cy.setCookie("theme", "dark");
    cy.request("GET", "/api/request-test?param1=value1&param2=value2", body).then((res) => {
        expect(res.headers["content-type"]).to.eq("application/json");
        expect(res.status).to.eq(200);
        expect(res.body).to.deep.eq({
            method: "GET",
            rawBody: JSON.stringify(body),
            cookies: { theme: "dark" },
            queryParams: { param1: ["value1"], param2: ["value2"] },
        });
    });
});
it("empty body", () => {
    cy.setCookie("theme", "dark");
    cy.request("GET", "/api/request-test").then((res) => {
        expect(res.headers["content-type"]).to.eq("application/json");
        expect(res.status).to.eq(200);
        expect(res.body.rawBody).to.be.null;
    });
});
it("form POST", () => {
    cy.setCookie("session-id", "123");
    const body = new URLSearchParams({ first: "Jane", last: "Doe" }).toString();
    cy.request({
        method: "POST",
        url: "/api/request-test",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: body,
    }).then((res) => {
        expect(res.headers["content-type"]).to.eq("application/json");
        expect(res.status).to.eq(200);
        expect(res.body).to.deep.eq({
            method: "POST",
            rawBody: body,
            cookies: { "session-id": "123" },
            queryParams: {},
        });
    });
});
export {};
