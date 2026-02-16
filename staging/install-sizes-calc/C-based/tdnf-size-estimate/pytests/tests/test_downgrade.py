#
# Copyright (C) 2019-2022 VMware, Inc. All Rights Reserved.
#
# Licensed under the GNU General Public License v2 (the "License");
# you may not use this file except in compliance with the License. The terms
# of the License are located in the COPYING file of this distribution.
#

import pytest


@pytest.fixture(scope="module", autouse=True)
def setup_test(utils):
    yield
    teardown_test(utils)


def teardown_test(utils):
    mpkg = utils.config["mulversion_pkgname"]
    utils.run(f"tdnf erase -y {mpkg}")


def test_downgrade_no_arg(utils):
    ret = utils.run("tdnf downgrade")
    assert ret["retval"] == 1011


def test_downgrade_with_test_repo(utils):
    mpkg = utils.config["mulversion_pkgname"]
    ret = utils.run(f"tdnf install -y {mpkg}")
    assert ret["retval"] == 0

    cmd = f"tdnf downgrade {mpkg}"
    ret = utils.run(cmd)
    # invalid response to y/n prompt
    assert ret["retval"] == 1033
    assert f"Downgrading: {mpkg}" in " ".join(ret["stdout"])

    cmd = f"{cmd} -y"
    ret = utils.run(cmd)
    assert ret["retval"] == 0
    # downgrade should go through
    assert f"Downgrading: {mpkg}" in " ".join(ret["stdout"])

    ret = utils.run(cmd)
    assert ret["retval"] == 0
    # already at least available version
    assert f"There is no downgrade path for {mpkg}" in " ".join(ret["stderr"])


def test_downgrade_install(utils):
    mpkg = utils.config["mulversion_pkgname"]
    ret = utils.run(f"tdnf install -y {mpkg}")
    assert ret["retval"] == 0

    ret = utils.run(f"tdnf downgrade -y {mpkg}")
    assert ret["retval"] == 0


def test_downgrade_with_lower_version(utils):
    mpkg = utils.config["mulversion_pkgname"]
    mpkg_lower = utils.config["mulversion_lower"]
    ret = utils.run(f"tdnf install -y {mpkg}-{mpkg_lower}")
    assert ret["retval"] == 0

    ret = utils.run(f"tdnf downgrade -y {mpkg}")
    assert ret["retval"] == 0


def test_downgrade_with_higher_version(utils):
    mpkg = utils.config["mulversion_pkgname"]
    ret = utils.run(f"tdnf install -y {mpkg}")
    assert ret["retval"] == 0

    mpkg_lower = utils.config["mulversion_lower"]
    ret = utils.run(f"tdnf downgrade -y {mpkg}-{mpkg_lower}")
    assert ret["retval"] == 0


def test_downgrade_with_invalid_version(utils):
    mpkg = utils.config["mulversion_pkgname"]
    ret = utils.run(f"tdnf downgrade -y {mpkg}-123.123.123")
    assert ret["retval"] == 1011


def test_downgrade_invalid_pkg_name(utils):
    ret = utils.run("tdnf downgrade -y invalid_pkg_name")
    assert ret["retval"] == 1011
