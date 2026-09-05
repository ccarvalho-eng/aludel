defmodule AludelDash.StorageConfigTest do
  use ExUnit.Case, async: true

  alias Aludel.Interfaces.Storage.Adapters.AWS
  alias Aludel.Interfaces.Storage.Adapters.GCS
  alias Aludel.Interfaces.Storage.Adapters.Local
  alias AludelDash.StorageConfig

  test "resolves local storage with an explicit persistent path" do
    assert {:ok, config} =
             StorageConfig.resolve(%{
               "ALUDEL_STORAGE_BACKEND" => "local",
               "ALUDEL_STORAGE_PATH" => "/data/aludel"
             })

    assert config == [
             adapter: Local,
             backends: [{Local, [root: "/data/aludel"]}]
           ]
  end

  test "resolves AWS storage without copying credentials into application config" do
    environment = %{
      "ALUDEL_STORAGE_BACKEND" => "aws",
      "AWS_S3_BUCKET" => "aludel-uploads",
      "AWS_REGION" => "us-east-1",
      "AWS_ACCESS_KEY_ID" => "access-value",
      "AWS_SECRET_ACCESS_KEY" => "secret-value",
      "AWS_SESSION_TOKEN" => "session-value"
    }

    assert {:ok, config} = StorageConfig.resolve(environment)

    assert config == [
             adapter: AWS,
             backends: [
               {AWS,
                [
                  bucket: "aludel-uploads",
                  region: "us-east-1",
                  access_key_id: {:system, "AWS_ACCESS_KEY_ID"},
                  secret_access_key: {:system, "AWS_SECRET_ACCESS_KEY"},
                  security_token: {:system, "AWS_SESSION_TOKEN"}
                ]}
             ]
           ]

    refute inspect(config) =~ "access-value"
    refute inspect(config) =~ "secret-value"
    refute inspect(config) =~ "session-value"
  end

  test "allows AWS runtime identity credentials" do
    assert {:ok, config} =
             StorageConfig.resolve(%{
               "ALUDEL_STORAGE_BACKEND" => "aws",
               "AWS_S3_BUCKET" => "aludel-uploads",
               "AWS_REGION" => "eu-west-1"
             })

    assert config == [
             adapter: AWS,
             backends: [
               {AWS,
                [
                  bucket: "aludel-uploads",
                  region: "eu-west-1",
                  access_key_id: [:pod_identity, :instance_role],
                  secret_access_key: [:pod_identity, :instance_role],
                  security_token: [:pod_identity, :instance_role]
                ]}
             ]
           ]
  end

  test "allows an explicit AWS key pair without a session token" do
    assert {:ok, config} =
             StorageConfig.resolve(%{
               "ALUDEL_STORAGE_BACKEND" => "aws",
               "AWS_S3_BUCKET" => "aludel-uploads",
               "AWS_REGION" => "us-east-1",
               "AWS_ACCESS_KEY_ID" => "access-value",
               "AWS_SECRET_ACCESS_KEY" => "secret-value"
             })

    [{AWS, backend_config}] = config[:backends]

    assert backend_config[:access_key_id] == {:system, "AWS_ACCESS_KEY_ID"}
    assert backend_config[:secret_access_key] == {:system, "AWS_SECRET_ACCESS_KEY"}
    refute Keyword.has_key?(backend_config, :security_token)
  end

  test "rejects partial or blank explicit AWS credentials" do
    base = %{
      "ALUDEL_STORAGE_BACKEND" => "aws",
      "AWS_S3_BUCKET" => "aludel-uploads",
      "AWS_REGION" => "us-east-1"
    }

    invalid_credentials = [
      %{"AWS_ACCESS_KEY_ID" => "access-value"},
      %{"AWS_SECRET_ACCESS_KEY" => "secret-value"},
      %{"AWS_SESSION_TOKEN" => "session-value"},
      %{"AWS_ACCESS_KEY_ID" => " ", "AWS_SECRET_ACCESS_KEY" => "secret-value"},
      %{"AWS_ACCESS_KEY_ID" => "access-value", "AWS_SECRET_ACCESS_KEY" => " "}
    ]

    for credentials <- invalid_credentials do
      assert {:error, :invalid_aws_credentials} =
               base
               |> Map.merge(credentials)
               |> StorageConfig.resolve()
    end
  end

  test "resolves GCS storage with optional requester-pays project" do
    assert {:ok, config} =
             StorageConfig.resolve(%{
               "ALUDEL_STORAGE_BACKEND" => "gcs",
               "GCS_BUCKET" => "aludel-uploads",
               "GCS_USER_PROJECT" => "billing-project"
             })

    assert config == [
             adapter: GCS,
             backends: [
               {GCS,
                [bucket: "aludel-uploads", goth: Aludel.Goth, user_project: "billing-project"]}
             ]
           ]
  end

  test "omits a blank requester-pays project" do
    assert {:ok, config} =
             StorageConfig.resolve(%{
               "ALUDEL_STORAGE_BACKEND" => "gcs",
               "GCS_BUCKET" => "aludel-uploads",
               "GCS_USER_PROJECT" => " "
             })

    assert config == [
             adapter: GCS,
             backends: [{GCS, [bucket: "aludel-uploads", goth: Aludel.Goth]}]
           ]
  end

  test "retains complete inactive backend configurations for existing documents" do
    assert {:ok, config} =
             StorageConfig.resolve(%{
               "ALUDEL_STORAGE_BACKEND" => "gcs",
               "ALUDEL_STORAGE_PATH" => "/data/aludel",
               "AWS_S3_BUCKET" => "aludel-archive",
               "AWS_REGION" => "us-east-1",
               "GCS_BUCKET" => "aludel-current"
             })

    assert config[:adapter] == GCS
    assert Keyword.keys(config[:backends]) == [Local, AWS, GCS]
  end

  test "rejects relative local paths and partial inactive backends" do
    assert {:error, {:invalid, "ALUDEL_STORAGE_PATH"}} =
             StorageConfig.resolve(%{
               "ALUDEL_STORAGE_BACKEND" => "local",
               "ALUDEL_STORAGE_PATH" => "tmp/uploads"
             })

    assert {:error, {:missing, "AWS_REGION"}} =
             StorageConfig.resolve(%{
               "ALUDEL_STORAGE_BACKEND" => "local",
               "ALUDEL_STORAGE_PATH" => "/data/aludel",
               "AWS_S3_BUCKET" => "partial-archive"
             })
  end

  test "rejects missing required backend variables" do
    cases = [
      {%{}, "ALUDEL_STORAGE_BACKEND"},
      {%{"ALUDEL_STORAGE_BACKEND" => "local"}, "ALUDEL_STORAGE_PATH"},
      {%{"ALUDEL_STORAGE_BACKEND" => "aws", "AWS_REGION" => "us-east-1"}, "AWS_S3_BUCKET"},
      {%{"ALUDEL_STORAGE_BACKEND" => "aws", "AWS_S3_BUCKET" => "bucket"}, "AWS_REGION"},
      {%{"ALUDEL_STORAGE_BACKEND" => "gcs"}, "GCS_BUCKET"}
    ]

    for {environment, variable} <- cases do
      assert {:error, {:missing, ^variable}} = StorageConfig.resolve(environment)
    end
  end

  test "rejects unsupported backends and invalid input" do
    assert {:error, {:unsupported_backend, "azure"}} =
             StorageConfig.resolve(%{"ALUDEL_STORAGE_BACKEND" => "azure"})

    assert {:error, :invalid_environment} = StorageConfig.resolve([])
  end
end
