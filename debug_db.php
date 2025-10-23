<?php
// Database debugging script
echo "<h2>Environment Variables Debug</h2>\n";
echo "<pre>\n";
echo "IS_DOCKER_DEPLOYMENT: " . (getenv('IS_DOCKER_DEPLOYMENT') ?: 'NOT SET') . "\n";
echo "DB_NAME: " . (getenv('DB_NAME') ?: 'NOT SET') . "\n";
echo "DB_USER: " . (getenv('DB_USER') ?: 'NOT SET') . "\n";
echo "DB_PASSWORD: " . (getenv('DB_PASSWORD') ? '[SET]' : 'NOT SET') . "\n";
echo "DB_HOST: " . (getenv('DB_HOST') ?: 'NOT SET (will default to drupal_db)') . "\n";
echo "DB_PORT: " . (getenv('DB_PORT') ?: 'NOT SET (will default to 3306)') . "\n";
echo "</pre>\n";

echo "<h2>Computed Database Configuration</h2>\n";
echo "<pre>\n";
if (getenv('IS_DOCKER_DEPLOYMENT') == 'true') {
    $db_config = [
        'database' => getenv('DB_NAME') ?: 'drupal',
        'username' => getenv('DB_USER') ?: 'drupal', 
        'password' => getenv('DB_PASSWORD') ?: 'drupal',
        'host' => getenv('DB_HOST') ?: 'drupal_db',
        'port' => getenv('DB_PORT') ?: '3306',
        'driver' => 'mysql',
    ];
    
    echo "Database config (Docker deployment detected):\n";
    print_r(array_merge($db_config, ['password' => '[HIDDEN]']));
    
    echo "\nTesting connection...\n";
    try {
        $dsn = sprintf("mysql:host=%s;port=%s;dbname=%s", 
                      $db_config['host'], 
                      $db_config['port'], 
                      $db_config['database']);
        
        $pdo = new PDO($dsn, $db_config['username'], $db_config['password']);
        echo "✅ Database connection successful!\n";
        
        $stmt = $pdo->query("SHOW TABLES");
        $tables = $stmt->fetchAll(PDO::FETCH_COLUMN);
        echo "Tables found: " . count($tables) . "\n";
        if (count($tables) > 0) {
            echo "Sample tables: " . implode(', ', array_slice($tables, 0, 5)) . "\n";
        }
        
    } catch (PDOException $e) {
        echo "❌ Database connection failed: " . $e->getMessage() . "\n";
    }
    
} else {
    echo "Docker deployment not detected (IS_DOCKER_DEPLOYMENT != 'true')\n";
    echo "Current value: '" . getenv('IS_DOCKER_DEPLOYMENT') . "'\n";
}
echo "</pre>\n";

echo "<h2>Network Connectivity Test</h2>\n";
echo "<pre>\n";
$host = getenv('DB_HOST') ?: 'drupal_db';
$port = getenv('DB_PORT') ?: '3306';

// Test if host is reachable
$connection = @fsockopen($host, $port, $errno, $errstr, 5);
if ($connection) {
    echo "✅ Network connection to $host:$port successful\n";
    fclose($connection);
} else {
    echo "❌ Network connection to $host:$port failed: $errstr ($errno)\n";
}
echo "</pre>\n";
?>