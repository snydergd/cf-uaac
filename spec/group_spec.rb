#--
# Cloud Foundry 2012.02.03 Beta
# Copyright (c) [2009-2012] VMware, Inc. All Rights Reserved.
#
# This product is licensed to you under the Apache License, Version 2.0 (the "License").
# You may not use this product except in compliance with the License.
#
# This product includes a number of subcomponents with
# separate copyright notices and license terms. Your use of these
# subcomponents is subject to the terms and conditions of the
# subcomponent's license, as noted in the LICENSE file.
#++

require 'spec_helper'
require 'cli'

module CF::UAA

describe GroupCli do

  include SpecHelper

  before :all do
    #Util.default_logger(:trace)
    Cli.configure("", nil, StringIO.new, true)
    setup_target(authorities: "clients.read,scim.read,scim.write,uaa.admin")
    Cli.run("token client get #{@test_client} -s #{@test_secret}").should be
    @test_user, @test_pwd = "SaM_#{Time.now.to_i}_", "correcthorsebatterystaple"
    @test_group = "JaNiToRs_#{Time.now.to_i}"
    @users = ["w", "r", "m", "n"].map { |v| @test_user + v }
    5.times { |i| @users << @test_user + i.to_s }
    @users.each { |u| Cli.run("user add #{u} -p #{@test_pwd} --email sam@example.com").should be }
    Cli.run("group add #{@test_group}").should be
    Cli.run("groups -a displayName").should be
    Cli.output.string.should include @test_group
  end

  after :all do
    Cli.run "context #{@test_client}"
    @users.each { |u| Cli.run("user delete #{u}") }
    @users.each { |u| Cli.run("user get #{u}").should be_nil }
    Cli.run("group delete #{@test_group}").should be
    cleanup_target
  end

  # actual user and group creation happens in before_all
  it "creates many users and a group as the test client" do
    @users.each { |u|
      Cli.run("user get #{u}").should be
      Cli.output.string.should include u
    }
    @users.each { |u| Cli.run("member add scim.me #{u}").should be }
    Cli.run("groups -a displayName").should be
    Cli.output.string.should include @test_group
    Cli.run("group get #{@test_group.upcase}").should be
    Cli.output.string.should include @test_group
    pending "real uaa can't add members to scim.read group yet" unless @stub_uaa
    Cli.run("member add scim.read #{@test_user}w").should be
  end

  it "gets attributes with case-insensitive attribute names" do
    Cli.run("groups -a dISPLAYNAME").should be
    Cli.output.string.should include @test_group
  end

  it "lists all users" do
    Cli.run("users -a UsernamE").should be
    @users.each { |u| Cli.output.string.should include u }
  end

  it "lists a page of users" do
    Cli.run("users -a userName --count 4 --start 5").should be
    Cli.output.string.should match /itemsPerPage: 4/i
    Cli.output.string.should match /startIndex: 5/i
  end

  it "adds one user to the group" do
    Cli.run("member add #{@test_group} #{@users[0]}").should be
    Cli.output.string.should include "success"
  end

  it "adds users to the group" do
    cmd = "member add #{@test_group}"
    @users.each { |u| cmd << " #{u.upcase}" }
    Cli.run(cmd).should be
    Cli.output.string.should include "success"
  end

  def check_members
    ids = Cli.output.string.scan(/.*value:\s+([^\s]+)/).flatten
    ids.size.should == @users.size
    @users.each { |u|
      Cli.run("user get #{u} -a id").should be
      Cli.output.string =~ /.*id:\s+([^\s]+)/
      ids.delete($1).should == $1
    }
    ids.should be_empty
  end

  it "lists all group members" do
    Cli.run("group get #{@test_group} -a memBers").should be
    check_members
  end

  it "adds one reader to the group" do
    Cli.run("group reader add #{@test_group} #{@test_user}r").should be
    Cli.output.string.should include "success"
  end

  it "adds one writer to the group" do
    Cli.run("group writer add #{@test_group} #{@test_user}w").should be
    Cli.run("group reader add #{@test_group} #{@test_user}w").should be
    Cli.output.string.should include "success"
  end

  it "gets readers and writers in the group" do
    Cli.run("group get #{@test_group}").should be
    Cli.output.string.should be
    #puts Cli.output.string
  end

  it "reads members as a reader" do
    Cli.run("token owner get #{@test_client} -s #{@test_secret} #{@test_user}r -p #{@test_pwd}").should be
    Cli.run("group get #{@test_group} -a memBers").should be
    ids = Cli.output.string.scan(/.*value:\s+([^\s]+)/).flatten
    @users.size.should == ids.size
  end

  it "can't write members as a reader" do
    pending "real uaa can't search for groups by name by scim.me/readers" unless @stub_uaa
    Cli.run("token owner get #{@test_client} -s #{@test_secret} #{@test_user}r -p #{@test_pwd}").should be
    Cli.run("member add #{@test_group} #{@test_user}z").should_not be
    Cli.output.string.should include "access_denied"
  end

  it "adds a member as a writer" do
    Cli.run "context #{@test_client}"
    Cli.run("user add #{@test_user}z -p #{@test_pwd} --email sam@example.com").should be
    @users << "#{@test_user}z"
    Cli.run("token owner get #{@test_client} -s #{@test_secret} #{@test_user}w -p #{@test_pwd}").should be
    Cli.run("member add #{@test_group} #{@test_user}z").should be
    Cli.run("group get #{@test_group} -a memBers").should be
    ids = Cli.output.string.scan(/.*value:\s+([^\s]+)/).flatten
    @users.size.should == ids.size
    # check_members
  end

  it "can't read members as a non-reader" do
    pending "real uaa still returns members even if user is not in readers list" unless @stub_uaa
    Cli.run("token owner get #{@test_client} -s #{@test_secret} #{@test_user}m -p #{@test_pwd}").should be
    Cli.run("group get #{@test_group}").should be_nil
    Cli.output.string.should include "NotFound"
  end

  it "deletes all members from a group" do
    Cli.run "context #{@test_client}"
    cmd = "member delete #{@test_group.downcase} "
    @users.each { |u| cmd << " #{u.downcase}" }
    Cli.run(cmd).should be
    Cli.output.string.should include "success"
    Cli.run("group get #{@test_group}")
    Cli.output.string.should_not match /members/i # they should really be gone
  end

end

end