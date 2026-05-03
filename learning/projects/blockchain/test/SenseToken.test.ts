import { expect } from "chai";
import { ethers } from "hardhat";

describe("SenseToken", () => {
  async function deployFixture() {
    const [admin, alice, bob] = await ethers.getSigners();
    const SenseToken = await ethers.getContractFactory("SenseToken");
    const token = await SenseToken.deploy(await admin.getAddress());
    return { token, admin, alice, bob };
  }

  it("starts with zero supply", async () => {
    const { token } = await deployFixture();
    expect(await token.totalSupply()).to.equal(0n);
  });

  it("grants DEFAULT_ADMIN_ROLE to the deployer-specified admin", async () => {
    const { token, admin } = await deployFixture();
    const DEFAULT_ADMIN_ROLE = await token.DEFAULT_ADMIN_ROLE();
    expect(await token.hasRole(DEFAULT_ADMIN_ROLE, await admin.getAddress())).to.equal(true);
  });

  it("rejects mint without MINTER_ROLE", async () => {
    const { token, alice } = await deployFixture();
    await expect(token.connect(alice).mint(await alice.getAddress(), 1n))
      .to.be.revertedWithCustomError(token, "AccessControlUnauthorizedAccount");
  });

  it("mints happy-path", async () => {
    const { token, admin, alice } = await deployFixture();
    const MINTER_ROLE = await token.MINTER_ROLE();
    await token.connect(admin).grantRole(MINTER_ROLE, await admin.getAddress());
    await token.connect(admin).mint(await alice.getAddress(), 1_000n);
    expect(await token.balanceOf(await alice.getAddress())).to.equal(1_000n);
    expect(await token.totalSupply()).to.equal(1_000n);
  });

  it("enforces the supply cap", async () => {
    const { token, admin, alice } = await deployFixture();
    const MINTER_ROLE = await token.MINTER_ROLE();
    await token.connect(admin).grantRole(MINTER_ROLE, await admin.getAddress());
    const cap = await token.MAX_SUPPLY();
    await expect(token.connect(admin).mint(await alice.getAddress(), cap + 1n))
      .to.be.revertedWithCustomError(token, "MaxSupplyExceeded");
  });

  it("tracks voting power via delegation", async () => {
    const { token, admin, alice } = await deployFixture();
    const MINTER_ROLE = await token.MINTER_ROLE();
    await token.connect(admin).grantRole(MINTER_ROLE, await admin.getAddress());
    await token.connect(admin).mint(await alice.getAddress(), 1_000n);
    // Voting power is zero until you self-delegate (OZ ERC20Votes semantics).
    expect(await token.getVotes(await alice.getAddress())).to.equal(0n);
    await token.connect(alice).delegate(await alice.getAddress());
    expect(await token.getVotes(await alice.getAddress())).to.equal(1_000n);
  });
});
