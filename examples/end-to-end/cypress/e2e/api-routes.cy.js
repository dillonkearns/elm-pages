it("JSON body", () => {
    cy.request("GET", "/api/greet", { first: "Dillon" }).then((res) => {
        expect(res.headers["content-type"]).to.eq("text/plain");
        expect(res.status).to.eq(200);
        expect(res.body).to.eq("Hello Dillon");
    });
});
it("JSON body with content-type metadata", () => {
    cy.request({
        method: "POST",
        url: "/api/greet",
        headers: { "Content-Type": "application/json; charset=utf-8" },
        body: JSON.stringify({ first: "Dillon" }),
    }).then((res) => {
        expect(res.headers["content-type"]).to.eq("text/plain");
        expect(res.status).to.eq(200);
        expect(res.body).to.eq("Hello Dillon");
    });
});
it("form post", () => {
    cy.request({
        method: "POST",
        url: "/api/greet",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: new URLSearchParams({ first: "Dillon" }).toString(),
    }).then((res) => {
        expect(res.headers["content-type"]).to.eq("text/plain");
        expect(res.status).to.eq(200);
        expect(res.body).to.eq("Hello Dillon");
    });
});
it("query param", () => {
    cy.request({
        method: "GET",
        url: "/api/greet?first=QueryParam",
    }).then((res) => {
        expect(res.headers["content-type"]).to.eq("text/plain");
        expect(res.status).to.eq(200);
        expect(res.body).to.eq("Hello QueryParam");
    });
});
it("expect query param when none present", () => {
    cy.request({
        method: "GET",
        url: "/api/greet",
        failOnStatusCode: false,
    }).then((res) => {
        expect(res.headers["content-type"]).to.eq("text/plain");
        expect(res.status).to.eq(400);
        expect(res.body).to.include(`Invalid request, expected either a JSON body or a 'first=' query param.`);
    });
});
it("missing expected query param", () => {
    cy.request({
        method: "GET",
        url: "/api/greet?name=Jane",
        failOnStatusCode: false,
    }).then((res) => {
        expect(res.headers["content-type"]).to.eq("text/plain");
        expect(res.status).to.eq(400);
        expect(res.body).to.include(`Invalid request, expected either a JSON body or a 'first=' query param.`);
    });
});
// it("multi-part form post", () => {
//   const formData = new FormData();
//   formData.set("first", "Multipart");
//   cy.request({
//     method: "POST",
//     url: "/api/greet",
//     body: formData,
//   }).then((res) => {
//     expect(res.headers["content-type"]).to.eq("text/plain");
//     expect(res.status).to.eq(200);
//     expect(Cypress.Blob.arrayBufferToBinaryString(res.body)).to.eq(
//       "Hello Multipart"
//     );
//   });
// });
it("decodes xml", () => {
    cy.request({
        method: "POST",
        url: "/api/xml",
        headers: { "Content-Type": "application/xml" },
        body: `
    <root>
        <path>
            <to>
                <string>
                    <value>SomeString</value>
                </string>
            </to>
        </path>
    </root>
`,
    }).then((res) => {
        expect(res.headers["content-type"]).to.eq("text/plain");
        expect(res.status).to.eq(200);
        expect(res.body).to.eq("SomeString");
    });
});
it("accepts xml content-type with extra whitespace and params", () => {
    cy.request({
        method: "POST",
        url: "/api/xml",
        headers: { "Content-Type": "application/xml ; charset=utf-8" },
        body: `
    <root>
        <path>
            <to>
                <string>
                    <value>SomeString</value>
                </string>
            </to>
        </path>
    </root>
`,
    }).then((res) => {
        expect(res.headers["content-type"]).to.eq("text/plain");
        expect(res.status).to.eq(200);
        expect(res.body).to.eq("SomeString");
    });
});
it("gives an error when there is no content-type header", () => {
    cy.request({
        method: "POST",
        url: "/api/xml",
        headers: {},
        body: `
    <root>
        <path>
            <to>
                <string>
                    <value>SomeString</value>
                </string>
            </to>
        </path>
    </root>
`,
        failOnStatusCode: false,
    }).then((res) => {
        expect(res.headers["content-type"]).to.eq("text/plain");
        expect(res.status).to.eq(400);
        expect(res.body).to.eq("Invalid request, expected a body with content-type application/xml.");
    });
});
it("handles XML body", () => {
    cy.request({
        method: "POST",
        url: "/api/multiple-content-types",
        headers: { "Content-Type": "application/xml ; charset=utf-8" },
        body: `
    <root>
        <path>
            <to>
                <string>
                    <value>SomeString</value>
                </string>
            </to>
        </path>
    </root>
`,
    }).then((res) => {
        expect(res.headers["content-type"]).to.eq("text/plain");
        expect(res.status).to.eq(200);
        expect(res.body).to.eq("SomeString");
    });
});
it("handles JSON body", () => {
    cy.request({
        method: "POST",
        url: "/api/multiple-content-types",
        body: { path: { to: { string: { value: "SomeString" } } } },
    }).then((res) => {
        expect(res.headers["content-type"]).to.eq("text/plain");
        expect(res.status).to.eq(200);
        expect(res.body).to.eq("SomeString");
    });
});
export {};
