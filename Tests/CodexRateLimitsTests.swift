import Foundation

// MARK: - Test Cases for Codex Rate Limits (Plus & Pro plans)

func testPlusPlanWithFiveHourAndWeekly() throws {
    let json = """
    {
      "ordinaryUsageAllowed": false,
      "rateLimits": {
        "limitId": "codex",
        "primary": {
          "usedPercent": 100,
          "windowDurationMins": 300,
          "resetsAt": 1790979046
        },
        "secondary": {
          "usedPercent": 89,
          "windowDurationMins": 10080,
          "resetsAt": 1791075623
        },
        "planType": "plus",
        "rateLimitReachedType": "rate_limit_reached"
      }
    }
    """
    let dto = try JSONDecoder().decode(CodexRateLimitsDTO.self, from: Data(json.utf8))
    
    assert(dto.planType == "plus", "Plan type should be plus")
    
    let fiveHour = dto.fiveHourRateLimit()
    assert(fiveHour != nil, "Plus plan must have a 5-hour rate limit")
    assert(fiveHour?.percent == 100, "5-hour rate limit should be 100%")
    assert(fiveHour?.utilization == 1.0, "5-hour utilization should be 1.0")
    
    let weekly = dto.weeklyRateLimit()
    assert(weekly != nil, "Plus plan must also have a weekly rate limit")
    assert(weekly?.percent == 89, "Weekly rate limit should be 89%")
    assert(weekly?.utilization == 0.89, "Weekly utilization should be 0.89")
    
    let usage = ServiceUsage(
        fiveHour: fiveHour,
        weekly: weekly,
        weeklySonnet: nil,
        planName: dto.planType?.capitalized
    )
    assert(usage.headline == fiveHour, "Headline for Plus plan should be fiveHour limit")
    assert(usage.planName == "Plus", "Plan name should be capitalized Plus")
    print("✅ testPlusPlanWithFiveHourAndWeekly passed")
}

func testProPlanWithWeeklyOnly() throws {
    let json = """
    {
      "rateLimits": {
        "limitId": "codex",
        "primary": {
          "usedPercent": 42,
          "windowDurationMins": 10080,
          "resetsAt": 1791075623
        },
        "planType": "pro"
      }
    }
    """
    let dto = try JSONDecoder().decode(CodexRateLimitsDTO.self, from: Data(json.utf8))
    
    assert(dto.planType == "pro", "Plan type should be pro")
    
    let fiveHour = dto.fiveHourRateLimit()
    assert(fiveHour == nil, "Pro plan should not have a 5-hour rate limit")
    
    let weekly = dto.weeklyRateLimit()
    assert(weekly != nil, "Pro plan must have a weekly rate limit")
    assert(weekly?.percent == 42, "Weekly rate limit should be 42%")
    
    let usage = ServiceUsage(
        fiveHour: fiveHour,
        weekly: weekly,
        weeklySonnet: nil,
        planName: dto.planType?.capitalized
    )
    assert(usage.headline == weekly, "Headline for Pro plan should fall back to weekly limit")
    assert(usage.planName == "Pro", "Plan name should be capitalized Pro")
    print("✅ testProPlanWithWeeklyOnly passed")
}

func testRateLimitsByLimitIdFallback() throws {
    let json = """
    {
      "rateLimits": null,
      "rateLimitsByLimitId": {
        "codex": {
          "limitId": "codex",
          "primary": {
            "usedPercent": 50,
            "windowDurationMins": 300,
            "resetsAt": 1790979046
          },
          "secondary": {
            "usedPercent": 60,
            "windowDurationMins": 10080,
            "resetsAt": 1791075623
          },
          "planType": "plus"
        }
      }
    }
    """
    let dto = try JSONDecoder().decode(CodexRateLimitsDTO.self, from: Data(json.utf8))
    
    assert(dto.planType == "plus", "Plan type should be resolved from rateLimitsByLimitId")
    assert(dto.fiveHourRateLimit()?.percent == 50, "5-hour rate limit should be 50%")
    assert(dto.weeklyRateLimit()?.percent == 60, "Weekly rate limit should be 60%")
    print("✅ testRateLimitsByLimitIdFallback passed")
}

func testMissingFieldsReturnNil() throws {
    let json = """
    {
      "rateLimits": {
        "primary": {
          "usedPercent": null,
          "windowDurationMins": 300,
          "resetsAt": null
        }
      }
    }
    """
    let dto = try JSONDecoder().decode(CodexRateLimitsDTO.self, from: Data(json.utf8))
    assert(dto.fiveHourRateLimit() == nil, "Missing fields should yield nil rate limit")
    print("✅ testMissingFieldsReturnNil passed")
}

func testProlitePlan() throws {
    let json = """
    {
      "ordinaryUsageAllowed": false,
      "rateLimits": {
        "limitId": "codex",
        "primary": {
          "usedPercent": 100,
          "windowDurationMins": 10080,
          "resetsAt": 1791373574
        },
        "secondary": null,
        "planType": "prolite",
        "rateLimitReachedType": "rate_limit_reached"
      },
      "accountId": "00000000-0000-0000-0000-000000000000"
    }
    """
    let dto = try JSONDecoder().decode(CodexRateLimitsDTO.self, from: Data(json.utf8))
    assert(dto.planType == "prolite", "Plan type should be prolite")
    assert(dto.accountId == "00000000-0000-0000-0000-000000000000", "AccountId should match")
    assert(dto.fiveHourRateLimit() == nil, "Prolite plan should not have a 5-hour rate limit")
    assert(dto.weeklyRateLimit()?.percent == 100, "Prolite weekly limit should be 100%")
    print("✅ testProlitePlan passed")
}

// MARK: - Run All Tests
@main
struct Runner {
    static func main() throws {
        print("Running Codex Rate Limits Tests...")
        try testPlusPlanWithFiveHourAndWeekly()
        try testProPlanWithWeeklyOnly()
        try testProlitePlan()
        try testRateLimitsByLimitIdFallback()
        try testMissingFieldsReturnNil()
        print("🎉 All tests passed successfully!")
    }
}
