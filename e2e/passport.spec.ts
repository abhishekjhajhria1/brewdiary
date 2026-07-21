import { test, expect, type Page } from "@playwright/test";

// The Taste Passport + Cartographer, driven as a person actually drives them.
//
// This file exists because of a specific failure: the Passport was built, unit-tested,
// lint-clean and compiled into a green build while being imported by absolutely nothing.
// Every gate we had said yes and no user could reach it. So these tests click.
//
// Everything here runs SIGNED OUT on purpose — store.ts keeps the diary in localStorage
// when logged out, so the whole derived layer (stamps, neighbours, recap) is reachable
// without a Supabase session. Charting needs auth, so we assert the affordance and its
// honest signed-out refusal rather than pretending to be logged in.

// The age gate stands in front of the entire app. Clear state, then walk through it.
async function enterApp(page: Page) {
  await page.goto("/");
  await page.evaluate(() => {
    window.localStorage.clear();
    window.sessionStorage.clear();
  });
  await page.goto("/");
  const dob = page.locator('input[type="date"]');
  if (await dob.isVisible().catch(() => false)) {
    await page.locator("select").first().selectOption("IN");
    await dob.fill("1990-01-01");
    await page.getByRole("button", { name: "Enter" }).click();
  }
  await expect(page.locator('input[type="date"]')).toBeHidden();
}

// Load a diary through the app's own JSON import (You → Settings). Deliberately NOT a
// localStorage poke: writing the store's key directly does not populate the running store,
// so a seeded key yields a silently empty diary and a test that passes for the wrong
// reason. Import is a real user path and goes through replaceAll(), which validates every
// row exactly as a real import would.
//
// It RETRIES, and that is not superstition. The file input is server-rendered, so it exists
// in the DOM before React attaches its onChange. setInputFiles fires a one-shot change event
// — if it lands pre-hydration the import is lost for good, and the test then fails on an
// empty diary looking exactly like an app bug. There is no reliable "hydrated" signal to
// wait for here (the Passport is SSR'd, so its markup appears before it is interactive), so
// we re-offer the file, under a fresh name, until the store actually takes it.
async function seedDiary(page: Page, drinks: string[]) {
  const today = new Date().toISOString().slice(0, 10);
  const rows = drinks.map((drink, i) => ({
    id: `e2e-${i}-${Date.now()}`,
    date: today,
    createdAt: new Date().toISOString(),
    drink,
  }));
  const headline = page.getByText(/famil(y|ies) & counting/);

  for (let attempt = 0; attempt < 8; attempt++) {
    await page.locator('input[type="file"]').setInputFiles({
      name: `diary-${attempt}.json`, // a new name each time, so the change event always fires
      mimeType: "application/json",
      buffer: Buffer.from(JSON.stringify(rows)),
    });
    if (await headline.isVisible({ timeout: 1500 }).catch(() => false)) return;
  }
  await expect(headline).toBeVisible({ timeout: 5_000 }); // fail with a real message
}

test.describe("the Taste Passport", () => {
  test("an empty diary shows the invitation, not a blank space", async ({ page }) => {
    await enterApp(page);
    await page.goto("/you");
    await expect(page.getByRole("heading", { name: "Palate" })).toBeVisible();
    await expect(page.getByText("your taste passport")).toBeVisible();
    await expect(page.getByText(/Log a drink and its family lights up/)).toBeVisible();
  });

  test("a logged drink lights its family, and the stamp opens", async ({ page }) => {
    await enterApp(page);
    await page.goto("/you");
    await seedDiary(page, ["Negroni"]);

    // The breadth headline is a COUNT and never a percentage or an "x of y".
    const headline = page.getByText(/famil(y|ies) & counting/);
    await expect(headline).toBeVisible();
    await expect(headline).not.toHaveText(/%|\bof\b/);

    // Tapping the stamp opens the sheet with the drink in the person's own words.
    await page.getByRole("button", { name: "Negroni", exact: false }).first().click();
    const sheet = page.getByRole("dialog");
    await expect(sheet).toBeVisible();
    await expect(sheet.getByText("What you've had")).toBeVisible();
    await expect(sheet.getByText("Negroni", { exact: true }).first()).toBeVisible();
  });

  test("repeats do not advance the map — breadth, never volume", async ({ page }) => {
    await enterApp(page);
    await page.goto("/you");

    await seedDiary(page, ["Negroni"]);
    const once = await page.getByText(/famil(y|ies) & counting/).innerText();

    // The same drink five times, plus a variant that folds into the same family.
    await seedDiary(page, ["Negroni", "negroni", "Negroni", "Negroni", "Negroni Sbagliato"]);
    const fiveTimes = await page.getByText(/famil(y|ies) & counting/).innerText();

    expect(fiveTimes).toBe(once); // the product rule, enforced in the UI a user sees
  });

  test("a novel drink becomes an off-map region and offers to be charted", async ({ page }) => {
    await enterApp(page);
    await page.goto("/you");
    await seedDiary(page, ["Zzyzx Fizzwallop"]);

    await expect(page.getByText("Off the map")).toBeVisible();
    await page.getByRole("button", { name: /Zzyzx Fizzwallop/ }).first().click();

    const sheet = page.getByRole("dialog");
    await expect(sheet.getByText(/The map doesn.t know this one yet/)).toBeVisible();
    await sheet.getByRole("button", { name: "Chart this" }).click();

    // The form is a real authoring act: spelling, family, world.
    await expect(sheet.getByLabel("Tidy spelling")).toHaveValue("Zzyzx Fizzwallop");
    await expect(sheet.getByLabel("Family it joins")).toBeVisible();

    // Signed out, sending is refused HONESTLY rather than silently failing.
    await sheet.getByRole("button", { name: "Send it in" }).click();
    await expect(sheet.getByRole("alert")).toContainText(/Sign in/i);
  });

  test("charting refuses a drink the dictionary already knows", async ({ page }) => {
    await enterApp(page);
    await page.goto("/you");
    await seedDiary(page, ["Zzyzx Fizzwallop"]);

    await page.getByRole("button", { name: /Zzyzx Fizzwallop/ }).first().click();
    const sheet = page.getByRole("dialog");
    await sheet.getByRole("button", { name: "Chart this" }).click();

    // Rename it to something already on the map: it must be caught BEFORE it is sent,
    // because accepting a duplicate forks the family in two on everyone's passport.
    await sheet.getByLabel("Tidy spelling").fill("Negroni");
    await sheet.getByRole("button", { name: "Send it in" }).click();
    await expect(sheet.getByRole("alert")).toContainText(/already has this/i);
  });
});

test.describe("the curiosity loop", () => {
  test("'Wander here' suggests unexplored families and saves one to the to-try list", async ({ page }) => {
    await enterApp(page);
    await page.goto("/you");
    await seedDiary(page, ["Negroni"]);

    // Scope to the card. A page-wide search by family name finds the STAMP chip in the
    // worlds grid first — same label, different button — so an unscoped locator quietly
    // clicks the wrong thing and opens the stamp sheet instead of saving a suggestion.
    const card = page.getByTestId("wander-here");
    await expect(card).toBeVisible();

    const chip = card.getByRole("button").first();
    const suggestion = (await chip.innerText()).replace("+ to try", "").trim();
    expect(suggestion).not.toBe("Negroni"); // never deepens what you already drink

    await chip.click();

    // Saving REMOVES the suggestion: palateNeighbours never proposes what's already on the
    // to-try list. So the confirmation is the chip leaving and the drink turning up in To
    // try — assert both, because "the button changed colour" would prove nothing reached
    // the wishlist at all.
    await expect(card.getByRole("button", { name: new RegExp(`^${suggestion}`) })).toHaveCount(0);
    await expect(page.getByText(suggestion, { exact: false }).first()).toBeVisible();
  });
});

test.describe("the weekly recap", () => {
  test("is off until asked for, then appears and can be dismissed", async ({ page }) => {
    await enterApp(page);
    await page.goto("/you");
    await seedDiary(page, ["Negroni"]);

    // Off by default — the app reveals nothing uninvited.
    await expect(page.getByText("Your week")).toBeHidden();

    await page.getByRole("switch", { name: "Weekly look-back" }).click();
    await expect(page.getByText("Your week")).toBeVisible();
    await expect(page.getByText(/new corner(s)? of the map/)).toBeVisible();

    // Dismissing buys silence, and it survives a reload.
    await page.getByRole("button", { name: "dismiss" }).click();
    await expect(page.getByText("Your week")).toBeHidden();
    await page.reload();
    await expect(page.getByText("Your week")).toBeHidden();
  });
});

test.describe("the shelf", () => {
  test("a pantry turns into things you can make, and never into a shopping list", async ({ page }) => {
    await enterApp(page);
    await page.goto("/you");
    await expect(page.getByRole("heading", { name: "Palate" })).toBeVisible();

    const add = page.getByPlaceholder(/Add an ingredient/);
    for (const item of ["gin", "campari", "sweet vermouth", "orange"]) {
      await add.fill(item);
      await add.press("Enter"); // the pantry input is a form — Enter is the real path, and
                                // "Add" is ambiguous: To try and the shelf both have one

    }

    // The shelf now makes something — and the Negroni is complete, so it leads.
    await expect(page.getByText(/Tonight you could make/)).toBeVisible();
    const negroni = page.getByRole("button", { name: /^Negroni/ }).first();
    await expect(negroni).toBeVisible();

    // Tapping it gives you the method — the feedback half of "what can I make".
    await negroni.click();
    await expect(page.getByText(/Equal parts, stirred over ice/)).toBeVisible();

    // THE RULE: nothing offers a drink the shelf can't finish. A Margarita needs tequila
    // and triple sec, neither of which is here — it must not appear at all, not even as
    // "one away", because for alcohol that is a purchase prompt.
    await expect(page.getByRole("button", { name: /^Margarita/ })).toHaveCount(0);
    await expect(page.getByText(/away|need|buy|shopping/i)).toHaveCount(0);
  });

  test("a soft shelf is served as well as a spirits one", async ({ page }) => {
    await enterApp(page);
    await page.goto("/you");
    await expect(page.getByRole("heading", { name: "Palate" })).toBeVisible();

    const add = page.getByPlaceholder(/Add an ingredient/);
    for (const item of ["coffee", "milk"]) {
      await add.fill(item);
      await add.press("Enter"); // the pantry input is a form — Enter is the real path, and
                                // "Add" is ambiguous: To try and the shelf both have one

    }
    await expect(page.getByText(/Tonight you could make/)).toBeVisible();
    await expect(page.getByRole("button", { name: /^Latte/ }).first()).toBeVisible();
  });
});
