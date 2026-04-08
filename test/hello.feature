Feature: Hello API

  Background:
    * url 'http://127.0.0.1:3000'

  Scenario: GET /hello returns expected greeting
    Given path '/hello'
    When method get
    Then status 200
    And match response == { message: 'world' }
