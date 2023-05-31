exports.handler =
  /**
   * @param {import('aws-lambda').APIGatewayProxyEvent} event
   * @param {any} context
   */
  async function (event, context) {
    return {
      body: JSON.stringify(new Date().toTimeString()),
      headers: {
        "Content-Type": "application/json",
      },
      statusCode: 200,
    };
  };
