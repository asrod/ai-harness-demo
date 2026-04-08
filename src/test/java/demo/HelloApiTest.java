package demo;

import com.intuit.karate.junit5.Karate;

/**
 * 运行仓库根目录下 {@code test/hello.feature}（经 pom.xml 复制到 test classpath）。
 */
public class HelloApiTest {

  @Karate.Test
  Karate testHello() {
    return Karate.run("classpath:hello.feature");
  }
}
