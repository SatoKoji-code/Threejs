<script type="module">
  // 既存のThree.js、GLTFLoaderの読み込み処理はそのまま使用

  // ==================================================
  // 運営側が変更する場所
  // 最後に「/」を付けてください
  // ==================================================
  const TILE_FOLDER_PATH = "./models/buildingA/";

  // ReCapから出力されるファイル名
  const TILE_PREFIX = "タイル";
  const TILE_EXTENSION = ".glb";

  // 安全装置
  const MAX_TILE_COUNT = 1000;

  async function loadAllTiles() {
    let loadedCount = 0;

    for (let i = 1; i <= MAX_TILE_COUNT; i++) {
      const fileName = `${TILE_PREFIX}${i}${TILE_EXTENSION}`;
      const filePath = `${TILE_FOLDER_PATH}${fileName}`;

      try {
        console.log(`読み込み開始：${filePath}`);

        const gltf = await gltfLoader.loadAsync(filePath);

        gltf.scene.name = fileName;
        gltf.scene.userData.tileNumber = i;

        scene.add(gltf.scene);

        loadedCount++;

        console.log(`読み込み完了：${fileName}`);
      } catch (error) {
        // 次の番号が存在しなければ読み込み終了
        console.log(
          `${fileName}が見つからないため、読み込みを終了します。`
        );

        break;
      }
    }

    if (loadedCount === 0) {
      alert(
        "タイルデータを読み込めませんでした。\n" +
        "TILE_FOLDER_PATHを確認してください。"
      );
      return;
    }

    console.log(`合計${loadedCount}個のタイルを読み込みました。`);

    // 全タイル読み込み後に必要ならカメラ位置を調整
    fitCameraToLoadedModels();
  }

  function fitCameraToLoadedModels() {
    const box = new THREE.Box3().setFromObject(scene);

    if (box.isEmpty()) {
      return;
    }

    const center = box.getCenter(new THREE.Vector3());
    const size = box.getSize(new THREE.Vector3());
    const maxSize = Math.max(size.x, size.y, size.z);

    const distance = maxSize * 1.5;

    camera.position.set(
      center.x + distance,
      center.y + distance * 0.5,
      center.z + distance
    );

    camera.lookAt(center);

    if (controls) {
      controls.target.copy(center);
      controls.update();
    }
  }

  async function init() {
    // 既存の初期化処理
    setupScene();
    setupCamera();
    setupRenderer();
    setupControls();

    // タイルを自動読み込み
    await loadAllTiles();

    animate();
  }

  init();
</script>