require_relative '../test_helper'

describe Project do
  let(:project) { projects(:test) }
  let(:author) { users(:deployer) }
  let(:url) { "git://foo.com:hello/world.git" }

  before { Project.any_instance.stubs(:valid_repository_url).returns(true) }

  it "generates a secure token when created" do
    Project.create!(name: "hello", repository_url: url).token.wont_be_nil
  end

  describe "#last_released_with_commit?" do
    it "returns true if the last release had that commit" do
      project.releases.create!(commit: "XYZ", author: author)
      assert project.last_released_with_commit?("XYZ")
    end

    it "returns false if the last release had a different commit" do
      project.releases.create!(commit: "123", author: author)
      assert !project.last_released_with_commit?("XYZ")
    end
  end

  it "has separate repository_directories for same project but different url" do
    project = projects(:test)
    other_project = Project.find(project.id)
    other_project.repository_url = 'git://hello'

    assert_not_equal project.repository_directory, other_project.repository_directory
  end

  describe "#create_release" do
    let(:project) { projects(:test) }
    let(:author) { users(:deployer) }

    it "returns false if there have been no releases" do
      assert !project.last_released_with_commit?("XYZ")
    end
  end

  describe "#create_release" do
    it "creates a new release" do
      release = project.create_release(commit: "foo", author: author)

      assert release.persisted?
    end

    it "defaults to release number 1" do
      release = project.create_release(commit: "foo", author: author)

      assert_equal 1, release.number
    end

    it "increments the release number" do
      project.releases.create!(author: author, commit: "bar", number: 41)
      release = project.create_release(commit: "foo", author: author)

      assert_equal 42, release.number
    end
  end

  describe "#changeset_for_release" do
    let(:project) { projects(:test) }
    let(:author) { users(:deployer) }


    it "returns changeset" do
      changeset = Changeset.new("url", "foo/bar", "a", "b")
      project.releases.create!(author: author, commit: "bar", number: 50)
      release = project.create_release(commit: "foo", author: author)

      Changeset.stubs(:find).with("bar/foo", "bar", "foo").returns(changeset)
      assert_equal changeset, project.changeset_for_release(release)
    end

    it "returns empty changeset" do
      changeset = Changeset.new("url", "foo/bar", "a", "a")
      release = project.releases.create!(author: author, commit: "bar", number: 50)

      Changeset.stubs(:find).with("bar/foo", nil, "bar").returns(changeset)
      assert_equal changeset, project.changeset_for_release(release)
    end
  end

  describe "#webhook_stages_for_branch" do
    it "returns the stages with mappings for the branch" do
      master_stage = project.stages.create!(name: "master_stage")
      production_stage = project.stages.create!(name: "production_stage")

      project.webhooks.create!(branch: "master", stage: master_stage)
      project.webhooks.create!(branch: "production", stage: production_stage)

      project.webhook_stages_for_branch("master").must_equal [master_stage]
      project.webhook_stages_for_branch("production").must_equal [production_stage]
    end
  end

  describe "#github_project" do
    it "returns the user/repo part of the repository URL" do
      project = Project.new(repository_url: "git@github.com:foo/bar.git")
      project.github_repo.must_equal "foo/bar"
    end

    it "handles user, organisation and repository names with hyphens" do
      project = Project.new(repository_url: "git@github.com:inlight-media/lighthouse-ios.git")
      project.github_repo.must_equal "inlight-media/lighthouse-ios"
    end

    it "handles repository names with dashes or dots" do
      project = Project.new(repository_url: "git@github.com:angular/angular.js.git")
      project.github_repo.must_equal "angular/angular.js"

      project = Project.new(repository_url: "git@github.com:zendesk/demo_apps.git")
      project.github_repo.must_equal "zendesk/demo_apps"
    end
  end

  describe "nested stages attributes" do
    let(:params) do
      {
        name: "Hello",
        repository_url: url,
        stages_attributes: {
          '0' => {
            name: 'Production',
            command: 'test command',
            command_ids: [commands(:echo).id]
          }
        }
      }
    end

    it 'creates a new project and stage'do
      project = Project.create!(params)
      stage = project.stages.where(name: 'Production').first
      stage.wont_be_nil
      stage.command.must_equal("echo hello\ntest command")
    end
  end

  describe 'project repository initialization' do

    before(:each) { unstub_project_callbacks }
    let(:repository_url) { 'git@github.com:zendesk/demo_apps.git' }

    it 'should not clean the project when the project is created' do
      project = Project.new(name: 'demo_apps', repository_url: repository_url)
      project.expects(:clean_old_repository).never
      project.save
    end

    it 'invokes the setup repository callback after creation' do
      project = Project.new(name: 'demo_apps', repository_url: repository_url)
      project.expects(:clone_repository).once
      project.save
    end

    it 'removes the cached repository after the project has been deleted' do
      project = Project.new(name: 'demo_apps', repository_url: repository_url)
      project.expects(:clone_repository).once
      project.expects(:clean_repository).once
      project.save
      project.soft_delete!
    end

    it 'removes the old repository and sets up the new repository if the repository_url is updated' do
      new_repository_url = 'git@github.com:angular/angular.js.git'
      project = Project.create(name: 'demo_apps', repository_url: repository_url)
      project.expects(:clone_repository).once
      original_repo_dir = project.repository.repo_cache_dir
      FileUtils.expects(:rm_rf).with(original_repo_dir).once
      project.update!(repository_url: new_repository_url)
      refute_equal(original_repo_dir, project.repository.repo_cache_dir)
    end

    it 'does not reset the repository if the repository_url is not changed' do
      project = Project.new(name: 'demo_apps', repository_url: repository_url)
      project.expects(:clone_repository).once
      project.expects(:clean_old_repository).never
      project.save!
      project.update!(name: 'new_name')
    end

    it 'sets the git repository on disk' do
      repository = mock()
      repository.expects(:clone!).once
      project = Project.new(id: 9999, name: 'demo_apps', repository_url: repository_url)
      project.stubs(:repository).returns(repository)
      project.send(:clone_repository).join
    end

    it 'fails to clone the repository and logs the error' do
      repository = mock()
      repository.expects(:clone!).returns(false).once
      project = Project.new(id: 9999, name: 'demo_apps', repository_url: repository_url)
      project.stubs(:repository).returns(repository)
      expected_message = "Could not clone git repository #{project.repository_url} for project #{project.name} - "
      Rails.logger.expects(:error).with(expected_message)
      project.send(:clone_repository).join
    end

    it 'logs that it could not clone the repository when there is an unexpected error' do
      error = 'Unexpected error while cloning the repository'
      repository = mock()
      repository.expects(:clone!).raises(error)
      project = Project.new(id: 9999, name: 'demo_apps', repository_url: repository_url)
      project.stubs(:repository).returns(repository)
      expected_message = "Could not clone git repository #{project.repository_url} for project #{project.name} - #{error}"
      Rails.logger.expects(:error).with(expected_message)
      project.send(:clone_repository).join
    end

    it 'does not validate with a bad repo url' do
      Project.any_instance.unstub(:valid_repository_url)
      project = Project.new(id: 9999, name: 'demo_apps', repository_url: 'my_bad_url')
      project.valid?.must_equal false
      project.errors.messages.must_equal repository_url: ["is not valid or accessible"]
    end
  end

  describe 'lock project' do

    let(:repository_url) { 'git@github.com:zendesk/demo_apps.git' }
    let(:project_id) { 999999 }

    after(:each) do
      MultiLock.locks = {}
    end

    it 'locks the project' do
      project = Project.new(id: project_id, name: 'demo_apps', repository_url: repository_url)
      output = StringIO.new
      MultiLock.locks[project_id].must_be_nil
      project.with_lock(output: output, holder: 'test', timeout: 2.seconds) do
        MultiLock.locks[project_id].wont_be_nil
      end
      MultiLock.locks[project_id].must_be_nil
    end

    it 'fails to aquire a lock if there is a lock already there' do
      MultiLock.locks = { project_id => 'test' }
      MultiLock.locks[project_id].wont_be_nil
      project = Project.new(id: project_id, name: 'demo_apps', repository_url: repository_url)
      output = StringIO.new
      project.with_lock(output: output, holder: 'test', timeout: 1.seconds) { output.puts("Can't get here") }
      output.string.include?("Can't get here").must_equal(false)
    end

    it 'executes the provided error callback if cannot acquire the lock' do
      MultiLock.locks = { project_id => 'test' }
      MultiLock.locks[project_id].wont_be_nil
      project = Project.new(id: project_id, name: 'demo_apps', repository_url: repository_url)
      output = StringIO.new
      callback = proc { output << 'using the error callback' }
      project.with_lock(output: output, holder: 'test', error_callback: callback, timeout: 1.seconds) do
        output.puts("Can't get here")
      end
      MultiLock.locks[project_id].wont_be_nil
      output.string.include?('using the error callback').must_equal(true)
      output.string.include?("Can't get here").must_equal(false)
    end

  end

end
